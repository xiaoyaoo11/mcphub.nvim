local curl = require("plenary.curl")
local Job = require("plenary.job")
local UI = require("mcphub.ui")

--- @class MCPHub
--- @field port number The port number for the MCP Hub server
--- @field config string Path to the MCP servers configuration file
--- @field ready boolean Whether the connection to server is ready
--- @field server_job Job|nil The server process job if we started it
--- @field client_id string Unique identifier for this client
--- @field is_owner boolean Whether this instance started the server
--- @field is_shutting_down boolean Whether we're in the process of shutting down
--- @field ui table UI instance for displaying information
local MCPHub = {}
MCPHub.__index = MCPHub

--- Create a new MCPHub instance
--- @param opts table
--- @return MCPHub|nil
function MCPHub:new(opts)
  -- Validate required options
  if not opts.port then
    vim.notify("MCPHub: port is required", vim.log.levels.ERROR)
    return nil
  end

  if not opts.config then
    vim.notify("MCPHub: config file path is required", vim.log.levels.ERROR)
    return nil
  end

  local self = setmetatable({}, MCPHub)
  self.port = opts.port
  self.config = opts.config
  -- State fields
  self.ready = false
  self.server_job = nil
  self.is_owner = false -- Whether we started the server
  self.is_shutting_down = false
  -- Initialize UI
  self.ui = UI:new()

  -- Generate unique client ID
  self.client_id = string.format("%s_%s_%s", vim.fn.getpid(), vim.fn.localtime(), vim.fn.rand())

  return self
end

--- Make an API request to the MCP Hub server
--- @param method string HTTP method
--- @param path string API path
--- @param body? table Optional request body
--- @return table|nil, string|nil Response data or error message
function MCPHub:api_request(method, path, body)
  -- Only skip ready check for health and verify_server
  if not self.ready and path ~= "health" then
    return nil, "Server not ready"
  end

  -- Prepare request options
  local opts = {
    url = string.format("http://localhost:%d/api/%s", self.port, path),
    method = method,
    timeout = 3000, -- 3 second timeout for regular requests
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json"
    }
  }

  if body then
    opts.body = vim.fn.json_encode(body)
  end

  -- Make request with protected call
  local ok, response = pcall(curl.request, opts)
  if not ok then
    return nil, "Network error: Request failed"
  end

  -- Handle missing response
  if not response then
    return nil, "Network error: No response"
  end

  -- Handle curl errors
  if response.exit ~= 0 then
    if response.exit == 28 then -- CURLE_OPERATION_TIMEDOUT
      return nil, "Network error: Request timed out"
    end
    return nil, string.format("Network error: Request failed (code %d)", response.exit)
  end

  -- Handle missing body
  if not response.body then
    return nil, "Network error: Empty response"
  end

  -- Parse response body
  local decode_ok, decoded = pcall(vim.fn.json_decode, response.body)
  if not decode_ok then
    -- Check if it's an error response first
    if response.status and response.status >= 400 then
      return nil, string.format("Server error (%d): %s", response.status, response.body)
    end
    return nil, "Invalid response: Not JSON"
  end

  -- Handle error status codes
  if response.status and response.status >= 400 then
    local error_msg = decoded.error or "Unknown error"
    return nil, string.format("Server error (%d): %s", response.status, error_msg)
  end

  return decoded, nil
end

--- Check if server is already running and is the correct type
--- @return boolean
function MCPHub:check_server()
  local response = self:api_request("GET", "health")
  if not response then
    return false
  end

  if response.server_id ~= "mcp-hub" then
    vim.notify("Invalid server type found on port " .. self.port, vim.log.levels.WARN)
    return false
  end

  if response.status ~= "ok" then
    vim.notify("Server is not ready on port " .. self.port, vim.log.levels.WARN)
    return false
  end

  return true
end

--- Start the MCP Hub server
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:start(opts)
  opts = opts or {}

  -- Check if server is already running
  if self:check_server() then
    vim.notify("MCP Hub server already running", vim.log.levels.INFO)
    self:handle_server_ready(opts)
    return
  end

  -- We're starting the server, mark as owner
  self.is_owner = true
  self.server_job = Job:new({
    command = "mcp-hub",
    args = { "--port", tostring(self.port), "--config", self.config },
    on_stdout = function(_, data)
      self:handle_stdout(data, opts)
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          vim.notify("MCP Hub error: " .. data, vim.log.levels.ERROR)
          if opts.on_error then
            opts.on_error(data)
          end
        end)
      end
    end,
    on_exit = function(j, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify(string.format("MCP Hub exited with code %d", code), vim.log.levels.ERROR)
          if opts.on_error then
            opts.on_error("Server exited unexpectedly")
          end
        end)
      end
      self.ready = false
      self.server_job = nil
    end
  })

  self.server_job:start()
end

function MCPHub:handle_stdout(data, opts)
  -- Parse JSON startup message
  if data and data:match("{.*}") then
    local ok, parsed = pcall(vim.json.decode, data)
    if ok and parsed.status == "ready" then
      -- Server started successfully
      vim.schedule(function()
        self:handle_server_ready(opts)
      end)
    end
  end
end

--- Handle successful server startup
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:handle_server_ready(opts)
  self.ready = true

  -- Then register client
  self:register_client(function(success)
    if success then
      self.ready = true
      vim.notify("MCP Hub server started and ready", vim.log.levels.INFO)
      if opts.on_ready then
        opts.on_ready(self)
      end
    else
      vim.notify("Failed to register client", vim.log.levels.ERROR)
      if opts.on_error then
        opts.on_error("Client registration failed")
      end
    end
  end)
end

--- Register client with server
--- @param callback? function Optional callback(success: boolean)
function MCPHub:register_client(callback)
  local response, err = self:api_request("POST", "client/register", {
    clientId = self.client_id
  })

  if err then
    vim.notify("Failed to register client: " .. err, vim.log.levels.ERROR)
    if callback then
      callback(false)
    end
    return
  end

  if callback then
    callback(true)
  end
end

--- Stop the MCP Hub server
---INFO:No need to terminate the serverjob as the server will autokill itself on unregistering after some grace period if there are
---no more clients listening.
function MCPHub:stop()
  -- Set flag to prevent reconnection attempts
  self.is_shutting_down = true

  if self.ready then
    -- Unregister client
    self:api_request("POST", "client/unregister", {
      clientId = self.client_id
    })
  end

  -- Clear state
  self.ready = false
  self.is_owner = false
  self.is_shutting_down = false
end

--- Check if the server is ready and reconnect if needed
--- @return boolean
function MCPHub:is_ready()
  return self.ready
end

--- Get server status information
--- @return table Status information
function MCPHub:get_status()
  local health = self:api_request("GET", "health")
  return {
    ready = self.ready,
    activeClients = health and health.activeClients or 0,
    servers = health and health.servers or {}
  }
end

--- Get available servers from latest health check
--- @return table List of servers
function MCPHub:get_servers()
  local data = self:api_request("GET", "servers")
  return data and data.servers or {}
end

--- Get server information if available
--- @param name string Server name
--- @return table|nil Server info
function MCPHub:get_server_info(name)
  local servers = self:get_servers()
  for _, server in ipairs(servers) do
    if server.name == name then
      return server
    end
  end
  return nil
end

--- Call a tool on a server
--- @param server_name string
--- @param tool_name string
--- @param args table
--- @return table|nil, string|nil Response data or error
function MCPHub:call_tool(server_name, tool_name, args)
  local response, err = self:api_request("POST", string.format("servers/%s/tools", server_name), {
    tool = tool_name,
    arguments = args or {}
  })

  if err then
    return nil, err
  end

  return response.result, nil
end

--- Access a server resource
--- @param server_name string
--- @param uri string
--- @return table|nil, string|nil Response data or error
function MCPHub:access_resource(server_name, uri)
  local response, err = self:api_request("POST", string.format("servers/%s/resources", server_name), {
    uri = uri
  })

  if err then
    return nil, err
  end

  return response.result, nil
end

--- Display current status using UI
function MCPHub:display_status()
  if not self:is_ready() then
    vim.notify("MCP Hub not ready. Use :lua require('mcphub').start_hub() to start", vim.log.levels.WARN)
    return
  end

  local status = self:get_status()
  self.ui:show({
    ready = self.ready,
    is_owner = self.is_owner,
    activeClients = status.activeClients,
    servers = status.servers,
    port = self.port
  })
end

return MCPHub

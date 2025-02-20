local curl = require("plenary.curl")
local Job = require("plenary.job")
local UI = require("mcphub.ui")
local log = require("mcphub.utils.log")

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
    log.error("Port is required")
    return nil
  end

  if not opts.config then
    log.error("Config file path is required")
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
--- @param opts? { body?: table, timeout?: number, skip_ready_check?: boolean }
--- @param callback function Callback function(response?: table, error?: string)
function MCPHub:api_request(method, path, opts, callback)
  opts = opts or {}

  -- Only skip ready check for health check
  if not opts.skip_ready_check and not self.ready and path ~= "health" then
    callback(nil, "Server not ready")
    return
  end

  -- Prepare request options
  local request_opts = {
    url = string.format("http://localhost:%d/api/%s", self.port, path),
    method = method,
    timeout = opts.timeout or 1000, -- Default 1s timeout
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json"
    }
  }

  -- Add body if provided
  if opts.body then
    request_opts.body = vim.fn.json_encode(opts.body)
  end

  -- Create job for better error handling
  local job = curl.request(vim.tbl_extend("force", request_opts, {
    callback = vim.schedule_wrap(function(response)
      if not response then
        callback(nil, "Network error: No response")
        return
      end

      -- Handle curl errors
      if response.exit ~= 0 then
        -- Handle specific curl exit codes
        local error_msg = ({
          [7] = "Connection refused - Server not running",
          [28] = "Request timed out"
        })[response.exit] or string.format("Request failed (code %d)", response.exit)

        callback(nil, "Network error: " .. error_msg)
        return
      end

      -- Handle non-200 status codes
      if response.status >= 400 then
        callback(nil, string.format("Server error (%d): %s", response.status, response.body))
        return
      end

      -- Parse response body
      if response.body then
        local decode_ok, decoded = pcall(vim.fn.json_decode, response.body)
        if not decode_ok then
          callback(nil, "Invalid response: Not JSON")
          return
        end
        callback(decoded)
      else
        callback(nil, "Empty response")
      end
    end),
    on_error = vim.schedule_wrap(function(err)
      local msg = err.message
      if type(err) == "string" then
        msg = err
      elseif err.code then
        msg = "Error code: " .. err.code
      else
        msg = "Unknown error"
      end
      callback(nil, "Network error: " .. msg)
    end)
  }))

  -- Add error handler for initial connection issues
  if not job then
    callback(nil, "Failed to create request")
  end
end

--- Check if server is running and handle connection asynchronously
--- @param callback function Callback function(is_running: boolean)
function MCPHub:check_server(callback)
  if self:is_ready() then
    callback(true)
    return
  end

  -- Quick health check
  self:api_request("GET", "health", {
    timeout = 1000,         -- 1000ms timeout for quick check
    skip_ready_check = true -- Skip ready check for health endpoint
  }, function(response, err)
    if err then
      log.debug("Health check: " .. err)
      callback(false)
      return
    end

    if not response or response.server_id ~= "mcp-hub" or response.status ~= "ok" then
      log.debug("Invalid server response")
      callback(false)
      return
    end

    callback(true)
  end)
end

--- Start the MCP Hub server
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:start(opts)
  opts = opts or {}

  -- Check if server is already running
  self:check_server(function(is_running)
    if is_running then
      log.debug("Server already running")
      self:handle_server_ready(opts)
      return
    end

    -- Start new server
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
            log.error("Server error: " .. data)
            if opts.on_error then
              opts.on_error(data)
            end
          end)
        end
      end,
      on_exit = function(j, code)
        if code ~= 0 then
          vim.schedule(function()
            log.error(string.format("Server exited with code %d", code))
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
  end)
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
      log.debug("Server ready")
      if opts.on_ready then
        opts.on_ready(self)
      end
    else
      log.error("Failed to register client")
      if opts.on_error then
        opts.on_error("Client registration failed")
      end
    end
  end)
end

--- Register client with server
--- @param callback? function Optional callback(success: boolean)
function MCPHub:register_client(callback)
  self:api_request("POST", "client/register", {
    body = {
      clientId = self.client_id
    }
  }, function(response, err)
    if err then
      log.error("Registration error: " .. err)
      if callback then
        callback(false)
      end
      return
    end

    if callback then
      callback(true)
    end
  end)
end

--- Stop the MCP Hub server
function MCPHub:stop()
  -- Set flag to prevent reconnection attempts
  self.is_shutting_down = true

  if self.ready then
    -- Unregister client
    self:api_request("POST", "client/unregister", {
      body = {
        clientId = self.client_id
      }
    }, function()
    end) -- We don't need to handle the response
  end

  -- Clear state
  self.ready = false
  self.is_owner = false
  self.is_shutting_down = false
end

--- Check if the server is ready
--- @return boolean
function MCPHub:is_ready()
  return self.ready
end

--- Get server status information
--- @param callback function Callback function(status: table)
function MCPHub:get_status(callback)
  self:api_request("GET", "health", nil, function(response)
    callback(response)
  end)
end

--- Get available servers
--- @param callback function Callback function(servers: table)
function MCPHub:get_servers(callback)
  self:api_request("GET", "servers", nil, function(response)
    callback(response and response.servers or {})
  end)
end

--- Get server information if available
--- @param name string Server name
--- @param callback function Callback function(server: table|nil)
function MCPHub:get_server_info(name, callback)
  self:get_servers(function(servers)
    for _, server in ipairs(servers) do
      if server.name == name then
        callback(server)
        return
      end
    end
    callback(nil)
  end)
end

--- Call a tool on a server
--- @param server_name string
--- @param tool_name string
--- @param args table
--- @param callback function Callback function(result: table|nil, error?: string)
function MCPHub:call_tool(server_name, tool_name, args, callback)
  self:api_request("POST", string.format("servers/%s/tools", server_name), {
    body = {
      tool = tool_name,
      arguments = args or {}
    }
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end
    callback(response.result)
  end)
end

--- Access a server resource
--- @param server_name string
--- @param uri string
--- @param callback function Callback function(result: table|nil, error?: string)
function MCPHub:access_resource(server_name, uri, callback)
  self:api_request("POST", string.format("servers/%s/resources", server_name), {
    body = {
      uri = uri
    }
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end
    callback(response.result)
  end)
end

--- Display current status using UI
function MCPHub:display_status()
  if not self:is_ready() then
    log.warn("Server not ready. Use :lua require('mcphub').start_hub() to start")
    return
  end

  self:get_status(function(data)
    if data then
      self.ui:show({
        is_ready = self:is_ready(),
        is_owner = self.is_owner,
        port = self.port,
        data = data
      })
    end
  end)
end

return MCPHub

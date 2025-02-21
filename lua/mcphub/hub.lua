local curl = require("plenary.curl")
local Job = require("plenary.job")
local UI = require("mcphub.ui")
local log = require("mcphub.utils.log")
local utils = require("mcphub.utils")
local handlers = require("mcphub.utils.handlers")

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
  setmetatable({}, MCPHub)
  -- Validate options
  local valid = utils.validate_opts(opts)
  if not valid then
    return nil
  end
  self.port = opts.port
  self.config = opts.config
  -- State fields
  self.ready = false
  self.server_job = nil
  self.is_owner = false -- Whether we started the server
  self.is_shutting_down = false
  -- Initialize UI
  self.ui = UI:new()
  self.job_output_stream = {}

  -- Generate unique client ID
  self.client_id = string.format("%s_%s_%s", vim.fn.getpid(), vim.fn.localtime(), vim.fn.rand())

  return self
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
      on_stdout = vim.schedule_wrap(function(_, data)
        table.insert(self.job_output_stream, {
          type = "stdout",
          data = data
        })
        -- Use unified handler for all server output
        handlers.ProcessHandlers.handle_output(data, {
          on_ready = function()
            self:handle_server_ready(opts)
          end,
          on_error = function(msg)
            if opts.on_error then
              opts.on_error(msg)
            end
          end
        })
      end),
      on_stderr = vim.schedule_wrap(function(_, data)
        self.job_output_stream = {
          type = "stderr",
          data = data
        }
        -- Use same handler for stderr
        handlers.ProcessHandlers.handle_output(data, {
          on_error = function(msg)
            if opts.on_error then
              opts.on_error(msg)
            end
          end
        })
      end),
      on_exit = vim.schedule_wrap(function(_, code)
        if code ~= 0 then
          log.error("Server exited unexpectedly")
          if opts.on_error then
            vim.schedule_wrap(function()
              opts.on_error("Server exited unexpectedly")
            end)
          end
        end
        self.ready = false
        self.server_job = nil
      end)
    })

    self.server_job:start()
  end)
end

--- Handle server ready state
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:handle_server_ready(opts)
  self.ready = true
  opts = opts or {}
  -- Register client
  self:register_client(function(success)
    if success then
      vim.schedule(function()
        if opts.on_ready then
          opts.on_ready(self)
        end
      end)
    else
      vim.schedule(function()
        log.error("Client registration failed")
        -- Error already logged in register_client
        if opts.on_error then
          opts.on_error("Client registration failed")
        end
      end)
    end
  end)
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

--- Make an API request to the MCP Hub server
--- @param method string HTTP method
--- @param path string API path
--- @param opts? { body?: table, timeout?: number, skip_ready_check?: boolean }
--- @param callback function Callback function(response?: table, error?: string)
function MCPHub:api_request(method, path, opts, callback)
  opts = opts or {}
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

  log.debug(string.format("API Request: %s %s %s", method, path, vim.inspect(opts)))
  -- Only skip ready check for health check
  if not opts.skip_ready_check and not self.ready and path ~= "health" then
    local error = "MCP Hub not ready. Make sure you call api_requests after ensuring the mcphub is ready."
    log.error(error)
    return
  end



  -- Create job for better error handling
  local job = curl.request(vim.tbl_extend("force", request_opts, {
    callback = vim.schedule_wrap(function(response)
      -- Check for curl-specific errors
      local curl_error = handlers.ResponseHandlers.handle_curl_error(response, request_opts)
      if curl_error then
        log.error(curl_error)
        callback(nil, curl_error)
        return
      end

      -- Check for HTTP errors
      local http_error = handlers.ResponseHandlers.handle_http_error(response, request_opts)
      if http_error then
        callback(nil, http_error)
        return
      end

      -- Parse JSON response
      local result, parse_error = handlers.ResponseHandlers.parse_json(response.body, request_opts)
      if parse_error then
        log.error(parse_error)
        callback(nil, parse_error)
        return
      end

      callback(result)
    end),
    on_error = vim.schedule_wrap(function(err)
      -- log.error(err)
      callback(nil, handlers.ResponseHandlers.process_error(err, {
        code = "NETWORK_ERROR",
        request = request_opts
      }))
    end)
  }))

  -- Handle initial connection issues
  if not job then
    log.error("Failed to create request")
    callback(nil, handlers.ResponseHandlers.process_error("Failed to create request", {
      code = "REQUEST_CREATION_ERROR",
      request = request_opts
    }))
  end
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
      log.error({
        code = "CLIENT_REGISTRATION_ERROR",
        message = "Failed to register client",
        data = {
          error = err
        }
      })
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

--- Get server status information
--- @param callback function Callback function(status: table)
function MCPHub:get_health(callback)
  self:api_request("GET", "health", nil, callback)
end

--- Get available servers
--- @param callback function Callback function(servers: table)
function MCPHub:get_servers(callback)
  self:api_request("GET", "servers", nil, function(response, err)
    callback(response and response.servers or nil, err)
  end)
end

--- Get server information if available
--- @param name string Server name
--- @param callback function Callback function(server: table|nil)
function MCPHub:get_server_info(name, callback)
  self:api_request("GET", string.format("servers/%s/info", name), nil, function(response, err)
    callback(response and response.server or nil, err)
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

--- Check if the server is ready
--- @return boolean
function MCPHub:is_ready()
  return self.ready
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

  -- -- Kill server process if we started it
  -- if self.server_job and self.is_owner then
  --   self.server_job:shutdown()
  -- end

  -- Clear state
  self.ready = false
  self.is_owner = false
  self.is_shutting_down = false
  self.server_job = nil
end

--- Display current status using UI
function MCPHub:display()
  if not self:is_ready() then
    log.error("Server not ready. Use :lua require('mcphub').start_hub() to start")
    return
  end

  self:get_health(function(data)
    if data then
      self.ui:show({
        output_stream = self.job_output_stream,
        -- is_ready = self:is_ready(),
        -- is_owner = self.is_owner,
        -- port = self.port,
        -- data = data
      })
    end
  end)
end

return MCPHub

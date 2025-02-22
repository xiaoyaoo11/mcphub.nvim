local curl = require("plenary.curl")
local Job = require("plenary.job")
local UI = require("mcphub.ui")
local log = require("mcphub.utils.log")
local utils = require("mcphub.utils")
local prompt_utils = require("mcphub.utils.prompt")
local handlers = require("mcphub.utils.handlers")

-- Default timeouts
local QUICK_TIMEOUT = 1000     -- 1s for quick operations like health checks
local TOOL_TIMEOUT = 30000     -- 30s for tool calls
local RESOURCE_TIMEOUT = 30000 -- 30s for resource access

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
  local self = setmetatable({}, MCPHub)
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
  self.state = nil
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
            opts.on_error("Server exited unexpectedly")
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
  -- update the state
  self:get_health({
    callback = function(response, err)
      if not err then
        self.state = response
      end
      -- Register client
      self:register_client({
        callback = function(response, err)
          if err then
            log.error("Client registration failed")
            -- Error already logged in register_client
            if opts.on_error then
              opts.on_error("Client registration failed")
            end
            return
          end
          if opts.on_ready then
            opts.on_ready(self)
          end
        end
      })
    end
  })
end

--- Check if server is running and handle connection
--- @param callback? function Optional callback(is_running: boolean)
--- @return boolean If no callback is provided, returns is_running
function MCPHub:check_server(callback)
  if self:is_ready() then
    if callback then
      callback(true)
      return
    end
    return true
  end

  -- Quick health check
  local opts = {
    timeout = QUICK_TIMEOUT, -- Quick timeout for health check
    skip_ready_check = true  -- Skip ready check for health endpoint
  }

  if callback then
    opts.callback = function(response, err)
      if err then
        log.debug("Health check: " .. err)
        callback(false)
        return
      end
      callback(response and response.server_id == "mcp-hub" and response.status == "ok")
    end
  end

  local response, err = self:api_request("GET", "health", opts)
  if not callback then
    if err then
      return false
    end
    return response and response.server_id == "mcp-hub" and response.status == "ok"
  end
end

--- Make an API request to the MCP Hub server
--- @param method string HTTP method
--- @param path string API path
--- @param opts? { body?: table, timeout?: number, skip_ready_check?: boolean, callback?: function }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:api_request(method, path, opts)
  opts = opts or {}
  local callback = opts.callback

  -- Prepare request options
  local request_opts = {
    url = string.format("http://localhost:%d/api/%s", self.port, path),
    method = method,
    timeout = opts.timeout or QUICK_TIMEOUT, -- Default 1s timeout
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
    if callback then
      log.error(error)
      callback(nil, error)
      return
    else
      return nil, error
    end
  end

  -- Handle response processing
  local function process_response(response)
    -- Check for curl-specific errors
    local curl_error = handlers.ResponseHandlers.handle_curl_error(response, request_opts)
    if curl_error then
      if callback then
        log.error(curl_error)
        callback(nil, curl_error)
        return
      else
        return nil, curl_error
      end
    end

    -- Check for HTTP errors
    local http_error = handlers.ResponseHandlers.handle_http_error(response, request_opts)
    if http_error then
      if callback then
        callback(nil, http_error)
        return
      else
        return nil, http_error
      end
    end

    -- Parse JSON response
    local result, parse_error = handlers.ResponseHandlers.parse_json(response.body, request_opts)
    if parse_error then
      if callback then
        log.error(parse_error)
        callback(nil, parse_error)
        return
      else
        return nil, parse_error
      end
    end

    if callback then
      callback(result)
    else
      return result
    end
  end

  -- Choose between sync and async based on callback presence
  if callback then
    -- Async mode
    local job = curl.request(vim.tbl_extend("force", request_opts, {
      callback = vim.schedule_wrap(function(response)
        process_response(response)
      end),
      on_error = vim.schedule_wrap(function(err)
        callback(nil, handlers.ResponseHandlers.process_error(err, {
          code = "NETWORK_ERROR",
          request = request_opts
        }))
      end)
    }))

    -- Handle initial connection issues
    if not job then
      local error = handlers.ResponseHandlers.process_error("Failed to create request", {
        code = "REQUEST_CREATION_ERROR",
        request = request_opts
      })
      log.error(error)
      callback(nil, error)
    end
  else
    -- Sync mode
    local response = curl.request(request_opts)
    return process_response(response)
  end
end

--- Register client with server
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
function MCPHub:register_client(opts)
  return self:api_request("POST", "client/register", vim.tbl_extend("force", {
    body = {
      clientId = self.client_id
    }
  }, opts or {}))
end

--- Get server status information
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_health(opts)
  local response, err = self:api_request("GET", "health", opts)
  if not opts or not opts.callback then
    if not err then
      self.state = response
    end
  end
  return response, err
end

--- Get available servers
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_servers(opts)
  return self:api_request("GET", "servers", opts)
end

--- Get server information if available
--- @param name string Server name
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_server_info(name, opts)
  return self:api_request("GET", string.format("servers/%s/info", name), opts)
end

--- Call a tool on a server
--- @param server_name string
--- @param tool_name string
--- @param args table
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
--[[
    | Scenario            | Example Response                                                                 |
    |---------------------|----------------------------------------------------------------------------------|
    | Text Output         | `{ "content": [{ "type": "text", "text": "Hello, World!" }], "isError": false }` |
    | Image Output        | `{ "content": [{ "type": "image", "data": "base64data...", "mimeType": "image/png" }], "isError": false }` |
    | Text Resource       | `{ "content": [{ "type": "resource", "resource": { "uri": "file.txt", "text": "Content" } }], "isError": false }` |
    | Binary Resource     | `{ "content": [{ "type": "resource", "resource": { "uri": "image.jpg", "blob": "base64data...", "mimeType": "image/jpeg" } }], "isError": false }` |
    | Error Case          | `{ "content": [], "isError": true }` (Note: Error details might be in JSON-RPC level) |
--]]
function MCPHub:call_tool(server_name, tool_name, args, opts)
  return self:api_request("POST", string.format("servers/%s/tools", server_name), vim.tbl_extend("force", {
    timeout = TOOL_TIMEOUT,
    body = {
      tool = tool_name,
      arguments = args or {}
    }
  }, opts or {}))
end

--- Access a server resource
--- @param server_name string
--- @param uri string
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
--[[
    | Scenario                     | Example Response                                                                 |
    |------------------------------|----------------------------------------------------------------------------------|
    | Text Resource                | `{ "contents": [{ "uri": "file.txt", "text": "This is the content of the file." }] }` |
    | Binary Resource without `mimeType` | `{ "contents": [{ "uri": "image.jpg", "blob": "base64encodeddata..." }] }`         |
    | Binary Resource with `mimeType` | `{ "contents": [{ "uri": "image.jpg", "mimeType": "image/jpeg", "blob": "base64encodeddata..." }] }` |
    | Multiple Resources           | `{ "contents": [{ "uri": "file1.txt", "text": "Content of file1" }, { "uri": "file2.png", "blob": "base64encodeddata..." }] }` |
    | No Resources (empty)         | `{ "contents": [] }`                                                             |
--]]
function MCPHub:access_resource(server_name, uri, opts)
  return self:api_request("POST", string.format("servers/%s/resources", server_name), vim.tbl_extend("force", {
    timeout = RESOURCE_TIMEOUT,
    body = {
      uri = uri
    }
  }, opts or {}))
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
    }) -- We don't need to handle the response
  end

  -- Clear state
  self.ready = false
  self.is_owner = false
  self.is_shutting_down = false
  self.server_job = nil
end

function MCPHub:get_state()
  return self.state
end

function MCPHub:ensure_ready()
  if not self:is_ready() then
    log.error("Server not ready. Make sure you call display after ensuring the mcphub is ready.")
    return false
  end
  return true
end

function MCPHub:get_active_servers_prompt()
  if not self:ensure_ready() then
    return ""
  end
  return prompt_utils.get_active_servers_prompt(self.state and self.state.servers or {})
end

function MCPHub:get_use_mcp_tool_prompt(opts)
  if not self:ensure_ready() then
    return ""
  end
  return prompt_utils.get_use_mcp_tool_prompt(opts)
end

function MCPHub:get_access_mcp_resource_prompt(opts)
  if not self:ensure_ready() then
    return ""
  end
  return prompt_utils.get_access_mcp_resource_prompt(opts)
end

--- Get all MCP system prompts
---@param opts? {use_mcp_tool_example?: string, access_mcp_resource_example?: string}
---@return {active_servers: string|nil, use_mcp_tool: string, access_mcp_resource: string}
function MCPHub:get_prompts(opts)
  if not self:ensure_ready() then
    return
  end
  opts = opts or {}
  return {
    active_servers = prompt_utils.get_active_servers_prompt(self.state and self.state.servers or {}),
    use_mcp_tool = prompt_utils.get_use_mcp_tool_prompt(opts.use_mcp_tool_example),
    access_mcp_resource = prompt_utils.get_access_mcp_resource_prompt(opts.access_mcp_resource_example)
  }
end

--- Display current status using UI
function MCPHub:display()
  if not self:ensure_ready() then
    return
  end
  self:get_health({
    callback = function(data)
      if data then
        self.ui:show({
          state = self.state,
          output_stream = self.job_output_stream
        })
      end
    end
  })
end

return MCPHub

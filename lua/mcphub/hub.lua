local curl = require("plenary.curl")
local Job = require("plenary.job")
local log = require("mcphub.utils.log")
local utils = require("mcphub.utils")
local prompt_utils = require("mcphub.utils.prompt")
local handlers = require("mcphub.utils.handlers")
local State = require("mcphub.state")

-- Default timeouts
local QUICK_TIMEOUT = 1000 -- 1s for quick operations like health checks
local TOOL_TIMEOUT = 30000 -- 30s for tool calls
local RESOURCE_TIMEOUT = 30000 -- 30s for resource access

--- @class MCPHub
--- @field port number The port number for the MCP Hub server
--- @field config string Path to the MCP servers configuration file
--- @field ready boolean Whether the connection to server is ready
--- @field server_job Job|nil The server process job if we started it
--- @field client_id string Unique identifier for this client
--- @field is_owner boolean Whether this instance started the server
--- @field is_shutting_down boolean Whether we're in the process of shutting down
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

    -- Generate unique client ID
    self.client_id = string.format("%s_%s_%s", vim.fn.getpid(), vim.fn.localtime(), vim.fn.rand())

    -- Update state
    State:update({
        server_state = {
            status = "disconnected",
            started_at = nil,
            pid = nil
        }
    }, "server")

    return self
end

--- Start the MCP Hub server
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:start(opts)
    opts = opts or {}

    -- Update state
    State:update({
        server_state = {
            status = "connecting"
        }
    }, "server")

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
            args = {"--port", tostring(self.port), "--config", self.config},
            on_stdout = vim.schedule_wrap(function(_, data)
                -- Add to state output
                State:add_output("stdout", data)

                -- Use unified handler for all server output
                handlers.ProcessHandlers.handle_output(data, {
                    on_ready = function()
                        self:handle_server_ready(opts)
                    end,
                    on_error = function(msg)
                        -- Console errors don't change server status
                        State:add_error({
                            type = "server",
                            message = msg
                        })
                        if opts.on_error then
                            opts.on_error(msg)
                        end
                    end
                })
            end),
            on_stderr = vim.schedule_wrap(function(_, data)
                -- Add to state output
                State:add_output("stderr", data)

                -- Use same handler for stderr
                handlers.ProcessHandlers.handle_output(data, {
                    on_error = function(msg)
                        State:add_error({
                            type = "server",
                            message = msg
                        })
                        if opts.on_error then
                            opts.on_error(msg)
                        end
                    end
                })
            end),
            on_exit = vim.schedule_wrap(function(j, code)
                if code ~= 0 then
                    log.error("Server exited unexpectedly")
                    State:add_error({
                        type = "server",
                        message = "Server exited unexpectedly",
                        details = {
                            exit_code = code
                        }
                    })
                    if opts.on_error then
                        opts.on_error("Server exited unexpectedly")
                    end
                end

                State:update({
                    server_state = {
                        status = "disconnected",
                        pid = nil
                    }
                }, "server")

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

    -- Update state
    State:update({
        server_state = {
            status = "connected",
            started_at = vim.loop.now(),
            pid = self.server_job and self.server_job.pid
        }
    }, "server")

    -- update the state
    self:get_health({
        callback = function(response, err)
            if err then
                State:add_error({
                    type = "server",
                    message = "Health check failed",
                    details = {
                        error = err
                    }
                })
            else
                State:update({
                    server_state = vim.tbl_extend("force", State.server_state, {
                        servers = response.servers or {}
                    })
                }, "server")
            end

            -- Register client
            self:register_client({
                callback = function(response, err)
                    if err then
                        log.error("Client registration failed")
                        State:add_error({
                            type = "server",
                            message = "Client registration failed",
                            details = {
                                error = err
                            }
                        })
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
--[[
Used to verify if server is running before starting a new one
Returns true if:
1. Server is already ready
2. Health check succeeds and server is mcp-hub
Returns false if:
1. Health check fails
2. Health check succeeds but server is not mcp-hub
--]]
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
        timeout = QUICK_TIMEOUT,
        skip_ready_check = true
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

--- Register client with server
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--[[
Register with running server to:
1. Let server know about this client
2. Get notifications about server events
3. Keep track of active clients
Response example:
{
  "clientId": "12345_1234567890_123",
  "registered": true,
  "activeClients": 3
}
--]]
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
    return self:api_request("GET", "health", opts)
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
--[[
Get detailed information about a specific server including:
1. Server status and uptime
2. Connected clients
3. Available tools and resources
4. Server-specific configuration
Response example:
{
  "name": "sequential-thinking",
  "status": "connected",
  "uptime": 3600,
  "lastStarted": "2025-02-23T04:36:09.881Z",
  "clients": ["client1", "client2"],
  "capabilities": {
    "tools": [...],
    "resources": [...]
  }
}
--]]
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
Execute a tool on a server. The response content varies by tool:
| Scenario            | Example Response                                              |
|---------------------|--------------------------------------------------------------|
| Text Output         | { "content": [{ "type": "text", "text": "Hello" }] }         |
| Image Output        | { "content": [{ "type": "image", "data": "base64..." }] }    |
| Text Resource       | { "content": [{ "type": "resource", "uri": "file.txt" }] }   |
| Binary Resource     | { "content": [{ "type": "resource", "uri": "image.jpg" }] }  |
| Error Case          | { "content": [], "isError": true }                           |
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
Access a resource from a server. The response varies by resource type:
| Resource Type | Example Response                                    |
|--------------|---------------------------------------------------|
| Text         | { "contents": [{ "uri": "file.txt", "text": "..." }] } |
| Binary       | { "contents": [{ "uri": "img.jpg", "blob": "..." }] }  |
| Multiple     | { "contents": [{ "uri": "1.txt" }, { "uri": "2.png" }] } |
| Not Found    | { "contents": [] }                                    |
--]]
function MCPHub:access_resource(server_name, uri, opts)
    return self:api_request("POST", string.format("servers/%s/resources", server_name), vim.tbl_extend("force", {
        timeout = RESOURCE_TIMEOUT,
        body = {
            uri = uri
        }
    }, opts or {}))
end

--- API request helper
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
        timeout = opts.timeout or QUICK_TIMEOUT,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        }
    }
    if opts.body then
        request_opts.body = vim.fn.json_encode(opts.body)
    end

    -- Only skip ready check for health check
    if not opts.skip_ready_check and not self.ready and path ~= "health" then
        local error = "MCP Hub not ready"
        State:add_error({
            type = "server",
            message = error
        })
        if callback then
            callback(nil, error)
            return
        else
            return nil, error
        end
    end

    -- Process response
    local function process_response(response)
        local curl_error = handlers.ResponseHandlers.handle_curl_error(response, request_opts)
        if curl_error then
            State:add_error({
                type = "server",
                message = curl_error,
                details = {
                    request = request_opts
                }
            })
            if callback then
                callback(nil, curl_error)
                return
            else
                return nil, curl_error
            end
        end

        local http_error = handlers.ResponseHandlers.handle_http_error(response, request_opts)
        if http_error then
            State:add_error({
                type = "server",
                message = http_error,
                details = {
                    request = request_opts
                }
            })
            if callback then
                callback(nil, http_error)
                return
            else
                return nil, http_error
            end
        end

        local result, parse_error = handlers.ResponseHandlers.parse_json(response.body, request_opts)
        if parse_error then
            State:add_error({
                type = "server",
                message = parse_error,
                details = {
                    request = request_opts
                }
            })
            if callback then
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

    if callback then
        -- Async mode
        curl.request(vim.tbl_extend("force", request_opts, {
            callback = vim.schedule_wrap(function(response)
                process_response(response)
            end),
            on_error = vim.schedule_wrap(function(err)
                local error = handlers.ResponseHandlers.process_error(err, {
                    code = "NETWORK_ERROR",
                    request = request_opts
                })
                State:add_error({
                    type = "server",
                    message = error,
                    details = {
                        request = request_opts
                    }
                })
                callback(nil, error)
            end)
        }))
    else
        -- Sync mode
        return process_response(curl.request(request_opts))
    end
end

--- Stop the MCP Hub server
--- Stops the server if we own it, otherwise just disconnects
function MCPHub:stop()
    self.is_shutting_down = true

    -- Unregister client
    self:api_request("POST", "client/unregister", {
        body = {
            clientId = self.client_id
        }
    })

    State:update({
        server_state = {
            status = "disconnected",
            pid = nil
        }
    }, "server")

    -- Clear state
    self.ready = false
    self.is_owner = false
    self.is_shutting_down = false
    self.server_job = nil
end

function MCPHub:is_ready()
    return self.ready
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
    return prompt_utils.get_active_servers_prompt(State.server_state.servers or {})
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
        active_servers = prompt_utils.get_active_servers_prompt(State.server_state.servers or {}),
        use_mcp_tool = prompt_utils.get_use_mcp_tool_prompt(opts.use_mcp_tool_example),
        access_mcp_resource = prompt_utils.get_access_mcp_resource_prompt(opts.access_mcp_resource_example)
    }
end

return MCPHub

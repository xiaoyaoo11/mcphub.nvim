local plenary_curl = require('plenary.curl')
local ui = require('mcphub.ui')

--- @class MCPHub
--- @field port number
--- @field config string
--- @field watch boolean
--- @field base_url string
local MCPHub = {}
MCPHub.__index = MCPHub

--- Create a new MCPHub instance
--- @param opts table
--- @return MCPHub
function MCPHub:new(opts)
    if type(opts.port) ~= 'number' then
        error('port must be a number')
    end

    if type(opts.config) ~= 'string' then
        error('config must be a string path')
    end

    local instance = {
        port = opts.port,
        config = opts.config,
        watch = opts.watch or false,
        base_url = string.format('http://localhost:%d/api', opts.port),
        ui = ui:new()
    }
    setmetatable(instance, self)
    return instance
end

--- Get the list of MCP servers and their status
--- @return table { servers: table[], timestamp: string }
function MCPHub:get_servers()
    local response = plenary_curl.get(self.base_url .. '/servers')
    if response.status ~= 200 then
        error('Failed to get server list')
    end
    return vim.json.decode(response.body)
end

--- Show the MCP Hub interface
function MCPHub:show()
    local data = self:get_servers()
    self.ui:show(data)
end

--- Initialize the MCPHub instance
function MCPHub:initialize()
    -- Check if the server is running
    local response = plenary_curl.get(self.base_url .. '/health')
    if response.status ~= 200 then
        error('MCP Hub server is not running')
    end
    vim.notify('Connected to MCP Hub server', vim.log.levels.INFO)
end

--- Get server info including tools and resources
--- @param server_name string Server name
--- @return table Server info with capabilities
function MCPHub:get_server_info(server_name)
    local response = plenary_curl.get(self.base_url .. '/servers/' .. server_name .. '/info')
    if response.status ~= 200 then
        error('Failed to get server info')
    end
    return vim.json.decode(response.body)
end

return MCPHub

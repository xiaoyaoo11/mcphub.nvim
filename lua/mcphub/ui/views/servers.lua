---@brief [[
--- Servers view for MCPHub UI
--- Shows detailed server information and management
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")

---@class ServersView
---@field super View
local ServersView = setmetatable({}, {
    __index = View
})
ServersView.__index = ServersView

function ServersView:new(ui)
    local instance = View:new(ui) -- Create base view
    return setmetatable(instance, ServersView)
end

-- Helper to format duration
local function format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Render server information
-- @param server table Server data
-- @param lines table Lines to append to
local function render_server(server, lines)
    -- Server header
    table.insert(lines, string.format("╭─ %s (%s)", server.name, server.status))

    -- Server details
    if server.uptime then
        table.insert(lines, string.format("│ Uptime: %s", format_uptime(server.uptime)))
    end
    if server.lastStarted then
        table.insert(lines, string.format("│ Started: %s", server.lastStarted))
    end

    -- Capabilities
    if server.capabilities then
        -- Tools
        if #server.capabilities.tools > 0 then
            table.insert(lines, "│")
            table.insert(lines, "│ Tools:")
            for _, tool in ipairs(server.capabilities.tools) do
                table.insert(lines, string.format("│  • %s", tool.name))
                if tool.description then
                    for _, line in ipairs(vim.split(tool.description, "\n")) do
                        table.insert(lines, string.format("│    %s", line))
                    end
                end
            end
        end

        -- Resources
        if #server.capabilities.resources > 0 then
            table.insert(lines, "│")
            table.insert(lines, "│ Resources:")
            for _, resource in ipairs(server.capabilities.resources) do
                table.insert(lines, string.format("│  • %s (%s)", resource.name, resource.mimeType))
            end
        end
    end

    -- Server footer
    table.insert(lines, "╰─")
    table.insert(lines, "")
end

function ServersView:render()
    -- Get base header
    local lines = self:render_header()

    -- Add servers section
    if State.setup_state == "failed" then
        table.insert(lines, "Setup Failed:")
        for _, err in ipairs(State.setup_errors) do
            table.insert(lines, string.format("• %s", err.message))
        end
    elseif State.setup_state == "in_progress" then
        table.insert(lines, "Setting up MCPHub...")
    else
        if State.server_state.status == "connected" then
            if State.server_state.servers and #State.server_state.servers > 0 then
                for _, server in ipairs(State.server_state.servers) do
                    render_server(server, lines)
                end
            else
                table.insert(lines, "No servers connected")
            end

            -- Show recent errors if any
            if #State.server_state.errors > 0 then
                table.insert(lines, "")
                table.insert(lines, "Recent Server Issues:")
                -- Show last 3 errors
                for i = #State.server_state.errors, math.max(1, #State.server_state.errors - 2), -1 do
                    local err = State.server_state.errors[i]
                    table.insert(lines, string.format("• %s", err.message))
                end
            end
        elseif State.server_state.status == "connecting" then
            table.insert(lines, "Connecting to server...")
        else
            table.insert(lines, "Server disconnected")
            if #State.server_state.errors > 0 then
                table.insert(lines, "")
                table.insert(lines, "Server Errors:")
                local err = State.server_state.errors[#State.server_state.errors]
                table.insert(lines, string.format("• %s", err.message))
            end
        end
    end

    -- Add help text
    table.insert(lines, "")
    table.insert(lines, "Press:")
    table.insert(lines, " <CR> - View server details   r - Refresh")
    table.insert(lines, " <ESC> - Return to main view  q - Close window")

    return lines
end

function ServersView:setup_keymaps()
    -- First set up the base view keymaps
    View.setup_keymaps(self)

    -- Add our own keymaps
    local function map(key, action, desc)
        vim.keymap.set('n', key, action, {
            buffer = self.ui.buffer,
            desc = desc,
            nowait = true
        })
    end

    -- Refresh server status
    map('r', function()
        if State.hub_instance then
            State.hub_instance:get_health()
        end
    end, "Refresh servers")
end

return ServersView

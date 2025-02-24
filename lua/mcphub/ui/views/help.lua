---@brief [[
--- Help view for MCPHub UI
--- Shows keyboard shortcuts and documentation
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")

---@class HelpView
---@field super View
local HelpView = setmetatable({}, {
    __index = View
})
HelpView.__index = HelpView

function HelpView:new(ui)
    local instance = View:new(ui) -- Create base view
    return setmetatable(instance, HelpView)
end

-- Basic navigation
local BASIC_COMMANDS = {{
    key = "q",
    desc = "Close window"
}, {
    key = "<ESC>",
    desc = "Return to main view"
}, {
    key = "S",
    desc = "Switch to servers view"
}, {
    key = "T",
    desc = "Switch to tools view"
}, {
    key = "R",
    desc = "Switch to resources view"
}, {
    key = "L",
    desc = "Switch to logs view"
}, {
    key = "?",
    desc = "Show this help"
}}

-- View-specific commands
local VIEW_COMMANDS = {
    servers = {{
        key = "r",
        desc = "Refresh server status"
    }},
    tools = {{
        key = "1-9",
        desc = "Select server/tool"
    }, {
        key = "<BS>",
        desc = "Go back to previous selection"
    }, {
        key = "<CR>",
        desc = "Execute selected tool"
    }, {
        key = "r",
        desc = "Refresh available tools"
    }},
    logs = {{
        key = "<TAB>",
        desc = "Switch between server/plugin logs"
    }, {
        key = "a",
        desc = "Toggle auto-scroll"
    }, {
        key = "c",
        desc = "Clear current log"
    }, {
        key = "r",
        desc = "Refresh logs"
    }}
}

-- Section divider
local function add_section(lines, title)
    table.insert(lines, "")
    table.insert(lines, title .. ":")
    table.insert(lines, string.rep("─", #title + 1))
end

function HelpView:render()
    -- Get base header
    local lines = self:render_header()

    -- Introduction
    table.insert(lines, "MCPHub Help")
    table.insert(lines, "")
    table.insert(lines, "MCPHub provides a UI for managing and interacting with MCP servers.")
    table.insert(lines, "The interface is divided into several views, each focusing on")
    table.insert(lines, "different aspects of server management.")

    -- Basic Navigation
    add_section(lines, "Basic Navigation")
    local max_key_len = 0
    for _, cmd in ipairs(BASIC_COMMANDS) do
        max_key_len = math.max(max_key_len, #cmd.key)
    end
    for _, cmd in ipairs(BASIC_COMMANDS) do
        table.insert(lines, string.format(" %s%s - %s", cmd.key, string.rep(" ", max_key_len - #cmd.key), cmd.desc))
    end

    -- Views Documentation
    add_section(lines, "Views")

    -- Main View
    table.insert(lines, "Main:")
    table.insert(lines, "  Displays server status, connected servers, and recent errors.")
    table.insert(lines, "  This is the default view when opening MCPHub.")

    -- Servers View
    table.insert(lines, "")
    table.insert(lines, "Servers:")
    table.insert(lines, "  Shows detailed information about connected servers including")
    table.insert(lines, "  uptime, capabilities, and available tools/resources.")
    for _, cmd in ipairs(VIEW_COMMANDS.servers) do
        table.insert(lines, string.format("  %s - %s", cmd.key, cmd.desc))
    end

    -- Tools View
    table.insert(lines, "")
    table.insert(lines, "Tools:")
    table.insert(lines, "  Allows selecting and executing server-provided tools.")
    table.insert(lines, "  Shows tool descriptions and input parameters.")
    for _, cmd in ipairs(VIEW_COMMANDS.tools) do
        table.insert(lines, string.format("  %s - %s", cmd.key, cmd.desc))
    end

    -- Logs View
    table.insert(lines, "")
    table.insert(lines, "Logs:")
    table.insert(lines, "  Displays server output and plugin logs with timestamps.")
    table.insert(lines, "  Supports auto-scrolling and log clearing.")
    for _, cmd in ipairs(VIEW_COMMANDS.logs) do
        table.insert(lines, string.format("  %s - %s", cmd.key, cmd.desc))
    end

    -- Additional Information
    add_section(lines, "Additional Information")
    table.insert(lines, "For more detailed documentation and examples, visit:")
    table.insert(lines, "https://github.com/username/mcphub.nvim")

    -- Error Reporting
    add_section(lines, "Error Reporting")
    table.insert(lines, "If you encounter any issues, please report them at:")
    table.insert(lines, "https://github.com/username/mcphub.nvim/issues")

    -- Server information
    if State.server_state.status == "connected" then
        add_section(lines, "Current Server")
        table.insert(lines, string.format("Status: %s", State.server_state.status))
        if State.server_state.pid then
            table.insert(lines, string.format("PID: %d", State.server_state.pid))
        end
        if State.server_state.started_at then
            table.insert(lines, string.format("Started: %s", os.date("%Y-%m-%d %H:%M:%S",
                math.floor(State.server_state.started_at / 1000))))
        end
    end

    return lines
end

return HelpView

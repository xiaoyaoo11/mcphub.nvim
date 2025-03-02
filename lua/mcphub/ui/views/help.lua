---@brief [[
--- Help view for MCPHub UI
--- Shows plugin documentation and keybindings
---@brief ]]
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")

---@class HelpView
---@field super View
local HelpView = setmetatable({}, {
    __index = View
})
HelpView.__index = HelpView

function HelpView:new(ui)
    local instance = View:new(ui, "help") -- Create base view with name
    return setmetatable(instance, HelpView)
end

function HelpView:get_initial_cursor_position()
    -- Position at start of Quick Start section
    local lines = self:render_header()
    return #lines + 2
end

function HelpView:render_quick_start()
    local lines = {}
    table.insert(lines, Text.section("Quick Start", {}, true)[1])

    local intro_text = [[
MCPHub manages MCP (Model Context Protocol) servers through a centralized config file while providing an intuitive interface for testing tools and resources. Perfect for LLM integration with your Neovim workflow.

Basic Usage:
• Browse server status and tools in Main view
• Test tools and resources in Servers view
• Monitor logs in Logs view
• Configure servers in Config view
• Get help with '?' key

Key Commands:
• :MCPHub - Toggle this window
• r - Refresh server status
• q - Close window
]]

    for _, line in ipairs(Text.multiline(intro_text, Text.highlights.muted)) do
        table.insert(lines, Text.pad_line(line))
    end

    table.insert(lines, Text.empty_line())
    return lines
end

function HelpView:render_navigation()
    local lines = {}
    table.insert(lines, Text.section("Views & Navigation", {}, true)[1])

    local nav_items = {{
        key = "H",
        name = "Home",
        desc = "Server status and overview"
    }, {
        key = "S",
        name = "Servers",
        desc = "Test tools and resources interactively"
    }, {
        key = "C",
        name = "Config",
        desc = "Server configuration"
    }, {
        key = "L",
        name = "Logs",
        desc = "Server and plugin logs"
    }, {
        key = "?",
        name = "Help",
        desc = "This help information"
    }}

    for _, item in ipairs(nav_items) do
        -- View name and shortcut
        local name_line = NuiLine():append(" " .. item.key .. " ", Text.highlights.header_shortcut):append(" - ",
            Text.highlights.muted):append(item.name, Text.highlights.success)
        table.insert(lines, Text.pad_line(name_line))

        -- View description
        local desc_line = NuiLine():append("  ", Text.highlights.muted):append(item.desc, Text.highlights.muted)
        table.insert(lines, Text.pad_line(desc_line))
        table.insert(lines, Text.pad_line(NuiLine()))
    end

    return lines
end

function HelpView:render_capabilities()
    local lines = {}
    table.insert(lines, Text.section("Working with Servers", {}, true)[1])

    local capabilities_text = [[
Testing Tools and Resources:
• In Servers view (press 'S'), browse available capabilities
• Select a tool/resource and press <CR> to interact
• Enter parameters for tools when prompted
• View raw or parsed responses
• Press <Esc> to exit capability mode

Server Management:
• Main view shows real-time status
• Logs view tracks activity and errors
• Config view for server settings
• Use 'r' to refresh status
]]

    for _, line in ipairs(Text.multiline(capabilities_text, Text.highlights.muted)) do
        table.insert(lines, Text.pad_line(line))
    end

    table.insert(lines, Text.empty_line())
    return lines
end

function HelpView:render_troubleshooting()
    local lines = {}
    table.insert(lines, Text.section("Troubleshooting", {}, true)[1])

    local help_text = [[
Common Issues:

1. Server Connection
   • Check port availability in Config view
   • Another server might be running
   • Check Logs view for errors

2. Tool/Resource Errors
   • Verify server is connected
   • Check parameter values
   • See Logs view for details

Need More Help?
• View logs for detailed errors
• Check MCP Inspector tool
• Visit: github.com/ravitemer/mcphub.nvim
]]

    for _, line in ipairs(Text.multiline(help_text, Text.highlights.muted)) do
        table.insert(lines, Text.pad_line(line))
    end

    return lines
end

function HelpView:render()
    -- Get base header
    local lines = self:render_header()

    -- Add help sections
    vim.list_extend(lines, self:render_quick_start())
    vim.list_extend(lines, self:render_navigation())
    vim.list_extend(lines, self:render_capabilities())
    vim.list_extend(lines, self:render_troubleshooting())

    return lines
end

return HelpView

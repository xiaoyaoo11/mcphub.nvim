---@brief [[
--- Help view for MCPHub UI
--- Shows plugin documentation and keybindings
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class HelpView
---@field super View
local HelpView = setmetatable({}, {
    __index = View,
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
    table.insert(lines, Text.pad_line(" Quick Start ", Text.highlights.header))

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
    table.insert(lines, Text.pad_line(" Views & Navigation ", Text.highlights.header))

    local nav_items = {
        {
            key = "H",
            name = "Home",
            desc = "Server status and overview",
        },
        {
            key = "C",
            name = "Config",
            desc = "Server configuration",
        },
        {
            key = "L",
            name = "Logs",
            desc = "Server and plugin logs",
        },
        {
            key = "?",
            name = "Help",
            desc = "This help information",
        },
    }

    for _, item in ipairs(nav_items) do
        -- View name and shortcut
        local name_line = NuiLine()
            :append(" " .. item.key .. " ", Text.highlights.header_shortcut)
            :append(" - ", Text.highlights.muted)
            :append(item.name, Text.highlights.success)
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
    table.insert(lines, Text.pad_line(" Working with servers ", Text.highlights.header))

    local capabilities_text = [[
Testing Tools and Resources:
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
    table.insert(lines, Text.pad_line(" Troubleshooting ", Text.highlights.header))

    local help_text = [[
Common Issues:

1. Environment Setup
   • Verify Node.js (>=18.0.0) is installed
   • Ensure Python is available
   • Check uvx installation
   • Most servers use npx/uvx commands - verify they work

2. Server Configuration
   • Ensure config file path is absolute
   • Verify JSON format with mcpServers key
   • Validate server command and args
   • Check port availability in Config view

3. Server Connection
   • Use MCP Inspector to verify operation
   • Try mcp-cli to test configuration
   • Check Logs view for errors
   • Test tools individually to isolate issues

4. Tool/Resource Errors
   • Verify server is connected
   • Check parameter values
   • Validate args match tool schema
   • See Logs view for details

Need More Help?
• MCP Inspector: github.com/modelcontextprotocol/inspector
• mcp-cli: github.com/wong2/mcp-cli
• Check Logs for detailed errors
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

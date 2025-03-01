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
    -- Position at start of About section
    local lines = self:render_header()
    return #lines + 2
end

function HelpView:render_about()
    local lines = {}
    table.insert(lines, Text.section("About MCP Hub", {}, true)[1])

    local about_text = [[
MCP Hub is a Neovim plugin for interacting with MCP (Model Context Protocol) servers.
It provides a central interface for managing multiple MCP servers and monitoring their
status and communication.

For more information, visit:
https://github.com/ravitemer/mcphub.nvim
]]

    for _, line in ipairs(Text.multiline(about_text, Text.highlights.muted)) do
        table.insert(lines, Text.pad_line(line))
    end

    table.insert(lines, Text.empty_line())
    return lines
end

function HelpView:render_navigation()
    local lines = {}
    table.insert(lines, Text.section("Navigation", {}, true)[1])

    local nav_items = {{
        key = "H",
        desc = "Home view - Overview and server status"
    }, {
        key = "S",
        desc = "Servers view - Server details and status"
    }, {
        key = "C",
        desc = "Config view - Server configuration"
    }, {
        key = "L",
        desc = "Logs view - Server and plugin logs"
    }, {
        key = "?",
        desc = "Help view - This help page"
    }, {
        key = "q",
        desc = "Close window"
    }}

    for _, item in ipairs(nav_items) do
        local line = NuiLine():append(item.key, Text.highlights.header_shortcut):append(" - ", Text.highlights.muted)
            :append(item.desc, Text.highlights.muted)
        table.insert(lines, Text.pad_line(line))
    end

    table.insert(lines, Text.empty_line())
    return lines
end

function HelpView:render_view_keys()
    local lines = {}
    table.insert(lines, Text.section("View-Specific Keys", {}, true)[1])

    local view_keys = {{
        name = "Main View",
        keys = {{
            key = "r",
            desc = "Refresh"
        }, {
            key = "R",
            desc = "Restart server"
        }}
    }, {
        name = "Servers View",
        keys = {{
            key = "<CR>",
            desc = "Open/Execute capability"
        }, {
            key = "<Esc>",
            desc = "Exit capability mode"
        }}
    }, {
        name = "Logs View",
        keys = {{
            key = "x",
            desc = "Clear logs"
        }}
    }, {
        name = "Config View",
        keys = {{
            key = "e",
            desc = "Edit configuration"
        }}
    }}

    for _, section in ipairs(view_keys) do
        -- Section name
        local name_line = NuiLine():append(section.name .. ":", Text.highlights.header)
        table.insert(lines, Text.pad_line(name_line))

        -- Keys
        for _, key in ipairs(section.keys) do
            local key_line = NuiLine():append("  "):append(key.key, Text.highlights.header_shortcut):append(" - ",
                Text.highlights.muted):append(key.desc, Text.highlights.muted)
            table.insert(lines, Text.pad_line(key_line))
        end
        table.insert(lines, Text.empty_line())
    end

    return lines
end

function HelpView:render_troubleshooting()
    local lines = {}
    table.insert(lines, Text.section("Troubleshooting", {}, true)[1])

    local help_text = [[
Common Issues:
• Server not connecting - Check if mcp-hub is installed globally
• Invalid config - Verify your config file format
• Version mismatch - Update mcp-hub to required version

For more help:
• Check server logs in the Logs view (L)
• View configuration in Config view (C)
• Visit the GitHub repository for documentation

If problems persist, please report issues on GitHub.
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
    vim.list_extend(lines, self:render_about())
    vim.list_extend(lines, self:render_navigation())
    vim.list_extend(lines, self:render_view_keys())
    vim.list_extend(lines, self:render_troubleshooting())

    return lines
end

return HelpView

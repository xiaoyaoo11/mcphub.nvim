---@brief [[
--- Text utilities for MCPHub
--- Provides text formatting, layout, and rendering utilities
---@brief ]]
local NuiText = require("mcphub.utils.nuitext")
local NuiLine = require("mcphub.utils.nuiline")
local hl = require("mcphub.utils.highlights")

local M = {}

-- Constants
M.HORIZONTAL_PADDING = 2

-- Export highlight groups for easy access
M.highlights = hl.groups

--- Split text into multiple NuiLines while preserving newlines
---@param content string Text that might contain newlines
---@param highlight? string Optional highlight group
---@return NuiLine[]
function M.multiline(content, highlight)
    local lines = {}
    for _, line in ipairs(vim.split(content, "\n", {
        plain = true
    })) do
        table.insert(lines, NuiLine():append(line, highlight))
    end
    return lines
end

--- Add horizontal padding to a line
---@param line NuiLine|string The line to pad
---@param highlight? string Optional highlight for string input
---@return NuiLine
function M.pad_line(line, highlight)
    local nui_line = NuiLine():append(string.rep(" ", M.HORIZONTAL_PADDING))

    if type(line) == "string" then
        nui_line:append(line, highlight)
    else
        nui_line:append(line)
    end

    return nui_line:append(string.rep(" ", M.HORIZONTAL_PADDING))
end

--- Create empty line with consistent padding
---@return NuiLine
function M.empty_line()
    return M.pad_line("")
end

--- Create a section with title and content
---@param title string Section title
---@param content NuiLine[] Content lines
---@param expanded boolean Whether section starts expanded
---@param highlight? string Optional highlight for title
---@return NuiLine[]
function M.section(title, content, expanded, highlight)
    local lines = {}
    local icon = expanded and "▾" or "▸"

    -- Add title with icon
    table.insert(lines, M.pad_line(NuiLine():append(icon .. " " .. title, highlight or M.highlights.header)))

    -- Add content if expanded
    if expanded then
        for _, line in ipairs(content) do
            table.insert(lines, M.pad_line(line))
        end
    end

    return lines
end

--- Create a divider line
---@param width number Total width
---@param highlight? string Optional highlight
---@return NuiLine
function M.divider(width, is_full)
    if is_full then
        return NuiLine():append(string.rep("-", width), M.highlights.muted)
    end
    return M.pad_line(string.rep("-", width - (M.HORIZONTAL_PADDING * 2)), M.highlights.muted)
end

--- Align text with proper padding
---@param text string
---@param width number
---@param align "left"|"center"|"right"
---@param highlight? string
---@return NuiLine
function M.align_text(text, width, align, highlight)
    local inner_width = width - (M.HORIZONTAL_PADDING * 2)
    local line = NuiLine.pad_text(text, inner_width, align, highlight)
    return M.pad_line(line)
end

---@param label string
---@param shortcut string
---@param selected boolean
---@return NuiLine
function M.create_button(label, shortcut, selected)
    local line = NuiLine()
    -- Start button group
    if selected then
        -- Selected button has full background
        line:append(" " .. shortcut, M.highlights.header_btn_shortcut)
        line:append(" " .. label .. " ", M.highlights.header_btn)
    else
        -- Unselected shows just shortcut highlighted
        line:append(" " .. shortcut, M.highlights.header_shortcut)
        line:append(" " .. label .. " ", M.highlights.header)
    end
    return line
end

--- The MCP Hub logo
---@param width number Window width for centering
---@return NuiLine[]
function M.render_logo(width)
    local logo_lines = ([[
╔╦╗╔═╗╔═╗  ╦ ╦╦ ╦╔╗ 
║║║║  ╠═╝  ╠═╣║ ║╠╩╗
╩ ╩╚═╝╩    ╩ ╩╚═╝╚═╝
]]):gmatch("[^\r\n]+")
    local lines = {}
    for line in logo_lines do
        table.insert(lines, M.align_text(line, width, "center", M.highlights.title))
    end
    return lines
end

--- Create header with buttons
---@param width number Window width
---@param current_view string Currently selected view
---@return NuiLine[]
function M.render_header(width, current_view)
    local lines = M.render_logo(width)
    -- Title
    -- table.insert(lines, M.align_text("MCP Hub", width, "center", M.highlights.title))
    -- table.insert(lines, NuiLine())

    -- Create buttons line
    local buttons = NuiLine()

    -- Add buttons with proper padding
    local btn_list = {{
        key = "H",
        label = "Hub",
        view = "main"
    }, {
        key = "S",
        label = "Servers",
        view = "servers"
    }, {
        key = "C",
        label = "Config",
        view = "config"
    }, {
        key = "L",
        label = "Logs",
        view = "logs"
    }, {
        key = "?",
        label = "Help",
        view = "help"
    }}

    for i, btn in ipairs(btn_list) do
        if i > 1 then
            buttons:append("  ") -- Add spacing between buttons
        end
        buttons:append(M.create_button(btn.label, btn.key, current_view == btn.view))
    end

    -- Center the buttons line
    local padding = math.floor((width - buttons:width()) / 2)
    if padding > 0 then
        table.insert(lines, NuiLine():append(string.rep(" ", padding)):append(buttons))
    else
        table.insert(lines, buttons)
    end

    -- Add separator line
    -- table.insert(lines, NuiLine())
    -- table.insert(lines, M.align_text(string.rep("─", math.min(width - 4, 60)), width, "center", M.highlights.muted))
    -- table.insert(lines, NuiLine())

    return lines
end

return M

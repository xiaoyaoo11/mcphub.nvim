--[[ Text utilities for MCPHub ]] ---
local NuiText = require("mcphub.utils.nuitext")
local NuiLine = require("mcphub.utils.nuiline")
local hl = require("mcphub.utils.highlights")

local M = {}

-- Export highlight groups for easy access
M.highlights = hl.groups

---@param text string
---@param width number
---@param align "left"|"center"|"right"
---@param highlight? string
---@return NuiLine
function M.align_text(text, width, align, highlight)
    return NuiLine.pad_text(text, width, align, highlight)
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
        key = "T",
        label = "Tools",
        view = "tools"
    }, {
        key = "R",
        label = "Resources",
        view = "resources"
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

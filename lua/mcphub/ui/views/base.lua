---@brief [[
--- Base view for MCPHub UI
--- Other views inherit from this
---@brief ]]
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local ns_id = vim.api.nvim_create_namespace("MCPHub")

---@class View
local View = {}
View.__index = View

function View:new(ui)
    local instance = {
        ui = ui, -- Parent UI instance
        lines = {} -- Content lines
    }

    return setmetatable(instance, self)
end

--- Get window width for centering
function View:get_width()
    return vim.api.nvim_win_get_width(self.ui.window)
end

--- Render header for view
--- @return NuiLine[] Header lines
function View:render_header()
    if self.ui.current_view == "main" then
        return {}
    end

    return Text.render_header(self:get_width(), self.ui.current_view)
end

--- Set up view-specific keymaps
function View:setup_keymaps()
    local function map(key, action, desc)
        vim.keymap.set('n', key, action, {
            buffer = self.ui.buffer,
            desc = desc,
            nowait = true
        })
    end

    -- Global navigation
    map('S', function()
        self.ui:switch_view('servers')
    end, "Switch to Servers view")

    map('T', function()
        self.ui:switch_view('tools')
    end, "Switch to Tools view")

    map('R', function()
        self.ui:switch_view('resources')
    end, "Switch to Resources view")

    map('C', function()
        self.ui:switch_view('config')
    end, "Switch to Config view")

    map('L', function()
        self.ui:switch_view('logs')
    end, "Switch to Logs view")

    map('?', function()
        self.ui:switch_view('help')
    end, "Switch to Help view")

    map('<ESC>', function()
        self.ui:switch_view('main')
    end, "Return to Main view")

    -- Close window
    map('q', function()
        self.ui:cleanup()
    end, "Close window")
end

--- Render view content
--- Should be overridden by child views
--- @return NuiLine[] Lines to render
function View:render()
    -- Get header
    local lines = self:render_header()

    -- Add content
    table.insert(lines, NuiLine():append("No content implemented for this view", Text.highlights.muted))

    return lines
end

--- Draw view content to buffer
function View:draw()
    -- Get buffer
    local buf = self.ui.buffer

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(buf, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    -- Get content lines
    local lines = self:render()

    -- Buffer line index
    local line_idx = 1

    -- Render each line with proper highlights
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            -- Convert plain strings to NuiLine
            line = NuiLine():append(line)
        end
        line:render(buf, ns_id, line_idx)
        line_idx = line_idx + 1
    end

    -- Make buffer unmodifiable
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Set up keymaps
    self:setup_keymaps()
end

--- Handle buffer enter
function View:on_enter()
    -- Override in child views if needed
end

--- Handle buffer leave
function View:on_leave()
    -- Override in child views if needed
end

return View

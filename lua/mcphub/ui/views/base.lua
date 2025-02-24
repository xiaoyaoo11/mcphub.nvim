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

-- Add divider
function View:divider()
    local width = self:get_width()
    local divider = Text.align_text(string.rep("-", width - 4), width, "center", Text.highlights.muted)
    return divider
end

function View:line()
    local line = NuiLine():append(string.rep(" ", self:get_width()))
    return line
end

--- Render header for view
--- @return NuiLine[] Header lines
function View:render_header()
    local lines = Text.render_header(self:get_width(), self.ui.current_view)
    table.insert(lines, self:divider())
    table.insert(lines, self:line())
    return lines
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
            -- split string into lines
            local lines = vim.split(line, "\n")
            for _, l in ipairs(lines) do
                line = NuiLine():append(l)
                line:render(buf, ns_id, line_idx)
                line_idx = line_idx + 1
            end
        else
            line:render(buf, ns_id, line_idx)
            line_idx = line_idx + 1
        end
    end

    -- Make buffer unmodifiable
    vim.api.nvim_buf_set_option(buf, "wrap", true)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

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

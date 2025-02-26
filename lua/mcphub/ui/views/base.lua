---@brief [[
--- Base view for MCPHub UI
--- Provides common view functionality and base for view inheritance
---@brief ]]
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local ns_id = vim.api.nvim_create_namespace("MCPHub")

local VIEW_TYPES = {
    SETUP_INDEPENDENT = {"logs", "help", "config"}
}

---@class View
---@field ui MCPHubUI Parent UI instance
---@field name string View name
---@field keymaps table<string, {action: function, desc: string}> View-specific keymaps
---@field active_keymaps string[] Currently active keymap keys
local View = {}
View.__index = View

function View:new(ui, name)
    local instance = {
        ui = ui,
        name = name or "unknown",
        keymaps = {},
        active_keymaps = {}
    }
    return setmetatable(instance, self)
end

--- Register a view-specific keymap
---@param key string Key to map
---@param action function Action to perform
---@param desc string Description for which-key
function View:add_keymap(key, action, desc)
    self.keymaps[key] = {
        action = action,
        desc = desc
    }
end

--- Apply all registered keymaps
function View:apply_keymaps()
    local buffer = self.ui.buffer

    -- First clear any existing view-specific keymaps
    for _, key in ipairs(self.active_keymaps) do
        pcall(vim.keymap.del, 'n', key, {
            buffer = buffer
        })
    end

    self.active_keymaps = {}

    -- Apply view's registered keymaps
    for key, map in pairs(self.keymaps) do
        vim.keymap.set('n', key, map.action, {
            buffer = buffer,
            desc = map.desc,
            nowait = true
        })
        table.insert(self.active_keymaps, key)
    end
end

--- Whether the view should show setup errors
---@return boolean
function View:should_show_setup_error()
    -- Don't show setup errors in certain views
    for _, name in ipairs(VIEW_TYPES.SETUP_INDEPENDENT) do
        if self.name == name then
            return false
        end
    end
    return true
end

--- Get window width for centering
function View:get_width()
    return vim.api.nvim_win_get_width(self.ui.window)
end

-- Add divider
function View:divider()
    return Text.divider(self:get_width())
end

--- Create an empty line
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

--- Render setup error state
---@param lines NuiLine[] Existing lines
---@return NuiLine[] Updated lines
function View:render_setup_error(lines)
    table.insert(lines, Text.pad_line(NuiLine():append("Setup Failed:", Text.highlights.error)))

    for _, err in ipairs(State.errors.setup) do
        -- Error message
        local line = NuiLine()
        line:append("⚠ ", Text.highlights.error)
        line:append(err.message, Text.highlights.error)
        table.insert(lines, Text.pad_line(line))

        -- Error details if any
        if err.details and next(err.details) then
            local errlines = vim.tbl_map(Text.pad_line, Text.multiline(vim.inspect(err.details), Text.highlights.muted))
            vim.list_extend(lines, errlines)
        end
    end

    -- Add help text
    table.insert(lines, Text.empty_line())

    return lines
end

--- Render progress state
---@param lines NuiLine[] Existing lines
---@return NuiLine[] Updated lines
function View:render_setup_progress(lines)
    -- Show progress message
    table.insert(lines, Text.align_text("Setting up MCPHub...", self:get_width(), "center", Text.highlights.info))

    -- Show recent log entries
    if State.output.stdout and #State.output.stdout > 0 then
        -- Get last few logs
        local recent = State.output.stdout[#State.output.stdout]
        if recent.data then
            local line = NuiLine():append("  "):append("◉ ", Text.highlights.info):append(recent.message,
                Text.highlights.muted)
            table.insert(lines, Text.pad_line(line))
        end
    end

    return lines
end

--- Render footer with keymaps
--- @return NuiLine[] Lines for footer
function View:render_footer()
    local lines = {}

    -- Add padding and divider
    table.insert(lines, Text.empty_line())
    table.insert(lines, self:divider())

    -- Get all keymaps
    local key_items = {}

    -- Add view-specific keymaps first
    for key, map in pairs(self.keymaps or {}) do
        table.insert(key_items, {
            key = key,
            desc = map.desc
        })
    end

    -- Add common close
    table.insert(key_items, {
        key = "q",
        desc = "Close window"
    })

    -- Format in a single line
    local keys_line = NuiLine()
    for i, key in ipairs(key_items) do
        if i > 1 then
            keys_line:append("  ", Text.highlights.muted)
        end
        keys_line:append(key.key, Text.highlights.header_shortcut):append(" ", Text.highlights.muted):append(key.desc,
            Text.highlights.muted)
    end

    table.insert(lines, Text.pad_line(keys_line))

    return lines
end

--- Render view content
--- Should be overridden by child views
--- @return NuiLine[] Lines to render
function View:render()
    -- Get base header
    local lines = self:render_header()

    -- Handle special states
    if State.setup_state == "failed" then
        if self:should_show_setup_error() then
            return self:render_setup_error(lines)
        end
    elseif State.setup_state == "in_progress" then
        if self:should_show_setup_error() then
            return self:render_setup_progress(lines)
        end
    end

    -- Views should override this to provide content
    table.insert(lines, Text.pad_line(NuiLine():append("No content implemented for this view", Text.highlights.muted)))

    -- Add footer
    vim.list_extend(lines, self:render_footer())

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

    -- Render each line with proper highlights
    local line_idx = 1
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            -- Handle string lines with potential newlines
            for _, l in ipairs(Text.multiline(line)) do
                l:render(buf, ns_id, line_idx)
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

    -- Apply keymaps
    self:apply_keymaps()
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

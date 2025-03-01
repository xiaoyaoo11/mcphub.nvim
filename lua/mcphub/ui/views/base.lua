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
---@field cursor_pos number[]|nil Last known cursor position
local View = {}
View.__index = View

function View:new(ui, name)
    local instance = {
        ui = ui,
        name = name or "unknown",
        keymaps = {},
        active_keymaps = {},
        cursor_pos = nil
    }
    return setmetatable(instance, self)
end

--- Get initial cursor position for this view
function View:get_initial_cursor_position()
    -- By default, position after header's divider
    local lines = self:render_header()
    if #lines > 0 then
        return #lines
    end
    return 1
end

--- Track current cursor position
function View:track_cursor()
    if self.ui.window and vim.api.nvim_win_is_valid(self.ui.window) then
        self.cursor_pos = vim.api.nvim_win_get_cursor(0)
    end
end

--- Set cursor position with bounds checking
---@param pos number[]|nil Position to set [line, col] or nil for last tracked position
---@param opts? {restore_col: boolean} Options for cursor setting (default: {restore_col: true})
function View:set_cursor(pos, opts)
    -- Use provided position or last tracked position
    local cursor = pos or self.cursor_pos
    if not cursor then
        return
    end
    -- Ensure window is valid
    if not (self.ui.window and vim.api.nvim_win_is_valid(self.ui.window)) then
        return
    end
    -- Ensure line is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    local new_pos = {math.min(cursor[1], line_count), cursor[2]}
    -- Set cursor
    vim.api.nvim_win_set_cursor(self.ui.window, new_pos)
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
    self:clear_keymaps()

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

function View:clear_keymaps()
    for _, key in ipairs(self.active_keymaps) do
        pcall(vim.keymap.del, 'n', key, {
            buffer = self.ui.buffer
        })
    end
    self.active_keymaps = {} -- Clear the active keymaps array after deletion
end

--- Save cursor position before leaving
function View:save_cursor_position()
    if self.ui.window and vim.api.nvim_win_is_valid(self.ui.window) then
        self.ui.cursor_states[self.name] = vim.api.nvim_win_get_cursor(0)
    end
end

--- Restore cursor position after entering
function View:restore_cursor_position()
    if not (self.ui.window and vim.api.nvim_win_is_valid(self.ui.window)) then
        return
    end

    local saved_pos = self.ui.cursor_states[self.name]
    if saved_pos then
        -- Ensure position is valid
        local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
        local new_pos = {math.min(saved_pos[1], line_count), saved_pos[2]}
        vim.api.nvim_win_set_cursor(0, new_pos)
    else
        -- Use initial position if no saved position
        local initial_line = self:get_initial_cursor_position()
        if initial_line then
            vim.api.nvim_win_set_cursor(0, {initial_line, 2})
        end
    end
end

--- Called before view is drawn (override in child views)
function View:before_enter()
end

--- Called after view is drawn and applied
function View:after_enter()
    self:apply_keymaps()
    self:restore_cursor_position()
end

--- Called before leaving view (override in child views)
function View:before_leave()
    self:save_cursor_position()
end

--- Called after leaving view
function View:after_leave()
    self:clear_keymaps()
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
function View:divider(is_full)
    return Text.divider(self:get_width(), is_full)
end

--- Create an empty line
function View:line()
    local line = NuiLine():append(string.rep(" ", self:get_width()))
    return line
end

function View:center(line, highlight)
    return Text.align_text(line, self:get_width(), "center", highlight)
end

--- Render header for view
--- @return NuiLine[] Header lines
function View:render_header(add_new_line)
    add_new_line = add_new_line == nil and true or add_new_line
    local lines = Text.render_header(self:get_width(), self.ui.current_view)
    table.insert(lines, self:divider())
    if add_new_line then
        table.insert(lines, self:line())
    end
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
    table.insert(lines, self:divider(true))

    -- Get all keymaps
    local key_items = {}

    -- Add view-specific keymaps first
    for key, map in pairs(self.keymaps or {}) do
        table.insert(key_items, {
            key = key,
            desc = map.desc
        })
    end

    table.insert(key_items, {
        key = "r",
        desc = "Refresh"
    })
    table.insert(key_items, {
        key = "R",
        desc = "Restart"
    })
    -- Add common close
    table.insert(key_items, {
        key = "q",
        desc = "Close"
    })

    -- Format in a single line
    local keys_line = NuiLine()
    for i, key in ipairs(key_items) do
        if i > 1 then
            keys_line:append("  ", Text.highlights.muted)
        end
        keys_line:append(" " .. key.key .. " ", Text.highlights.header_shortcut):append(" ", Text.highlights.muted)
            :append(key.desc, Text.highlights.muted)
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

    return lines
end

--- Draw view content to buffer
function View:draw()
    -- Track cursor position before drawing
    self:track_cursor()

    -- Get buffer
    local buf = self.ui.buffer

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(buf, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    -- Get content and footer lines
    local lines = self:render()
    local footer_lines = self:render_footer()

    -- Calculate if we need padding
    local win_height = vim.api.nvim_win_get_height(self.ui.window)
    local content_height = #lines
    local total_needed = win_height - content_height - #footer_lines

    -- Add padding if needed
    if total_needed > 0 then
        for _ = 1, total_needed do
            table.insert(lines, Text.empty_line())
        end
    end

    -- Add footer at the end
    vim.list_extend(lines, footer_lines)

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

    -- Restore cursor position after drawing
    self:set_cursor()
end

return View

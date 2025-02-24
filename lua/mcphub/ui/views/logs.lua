---@brief [[
--- Logs view for MCPHub UI
--- Shows server output and plugin logs
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")

---@class LogsView
---@field super View
local LogsView = setmetatable({}, {
    __index = View
})
LogsView.__index = LogsView

---@class LogsViewState
---@field current_tab string Current tab (server|plugin)
---@field auto_scroll boolean Whether to auto scroll to bottom
local view_state = {
    current_tab = "server",
    auto_scroll = true
}

function LogsView:new(ui)
    local instance = View:new(ui) -- Create base view
    return setmetatable(instance, LogsView)
end

-- Format timestamp
local function format_time(timestamp)
    return os.date("%H:%M:%S", math.floor(timestamp / 1000))
end

-- Render server output section
local function render_server_output(lines)
    table.insert(lines, "Server Output:")

    -- Show stdout
    if #State.output.stdout > 0 then
        for _, entry in ipairs(State.output.stdout) do
            if entry.time and entry.data then
                table.insert(lines, string.format("[%s] %s", format_time(entry.time), entry.data))
            end
        end
    else
        table.insert(lines, "  No output available")
    end

    -- Show stderr if any
    if #State.output.stderr > 0 then
        table.insert(lines, "")
        table.insert(lines, "Server Errors:")
        for _, entry in ipairs(State.output.stderr) do
            if entry.time and entry.data then
                table.insert(lines, string.format("[%s] %s", format_time(entry.time), entry.data))
            end
        end
    end
end

-- Render plugin logs section
local function render_plugin_logs(lines)
    table.insert(lines, "Plugin Logs:")

    local has_logs = false
    -- Show logs by level, most severe first
    local levels = {"error", "warn", "info", "debug"}
    for _, level in ipairs(levels) do
        local logs = State.logs[level]
        if #logs > 0 then
            has_logs = true
            for _, entry in ipairs(logs) do
                if entry.time and entry.message then
                    -- Format based on message type
                    if type(entry.message) == "table" then
                        if entry.message.formatted then
                            table.insert(lines, string.format("[%s] [%s] %s", format_time(entry.time), level:upper(),
                                entry.message.formatted))
                        else
                            table.insert(lines, string.format("[%s] [%s] %s", format_time(entry.time), level:upper(),
                                vim.inspect(entry.message.raw)))
                        end
                    else
                        table.insert(lines, string.format("[%s] [%s] %s", format_time(entry.time), level:upper(),
                            tostring(entry.message)))
                    end
                end
            end
        end
    end

    if not has_logs then
        table.insert(lines, "  No logs available")
    end
end

function LogsView:render()
    -- Get base header
    local lines = self:render_header()

    -- Add tab selection
    table.insert(lines,
        string.format("[ %s ] %s  [ %s ] %s", view_state.current_tab == "server" and "x" or " ", "Server Output",
            view_state.current_tab == "plugin" and "x" or " ", "Plugin Logs"))
    table.insert(lines, string.rep("─", 50))
    table.insert(lines, "")

    -- Show content based on selected tab
    if view_state.current_tab == "server" then
        render_server_output(lines)
    else
        render_plugin_logs(lines)
    end

    -- Add help text
    table.insert(lines, "")
    table.insert(lines, "Press:")
    table.insert(lines, " <TAB> - Switch view   a - Toggle auto-scroll")
    table.insert(lines, " c - Clear logs        r - Refresh")
    table.insert(lines, " <ESC> - Return to main view  q - Close window")

    return lines
end

function LogsView:setup_keymaps()
    -- First set up the base view keymaps
    View.setup_keymaps(self)

    -- Add our own keymaps
    local function map(key, action, desc)
        vim.keymap.set('n', key, action, {
            buffer = self.ui.buffer,
            desc = desc,
            nowait = true
        })
    end

    -- Switch tabs
    map('<TAB>', function()
        view_state.current_tab = view_state.current_tab == "server" and "plugin" or "server"
        self:render()
    end, "Switch view")

    -- Toggle auto-scroll
    map('a', function()
        view_state.auto_scroll = not view_state.auto_scroll
        vim.notify(string.format("Auto-scroll %s", view_state.auto_scroll and "enabled" or "disabled"))
    end, "Toggle auto-scroll")

    -- Clear logs
    map('c', function()
        if view_state.current_tab == "server" then
            State.output.stdout = {}
            State.output.stderr = {}
        else
            for _, level in pairs(State.logs) do
                level = {}
            end
        end
        self:render()
    end, "Clear logs")

    -- Refresh
    map('r', function()
        self:render()
    end, "Refresh view")
end

function LogsView:on_enter()
    -- Auto scroll to bottom on enter
    if view_state.auto_scroll then
        vim.schedule(function()
            local last_line = vim.api.nvim_buf_line_count(self.ui.buffer)
            vim.api.nvim_win_set_cursor(self.ui.window, {last_line, 0})
        end)
    end
end

return LogsView

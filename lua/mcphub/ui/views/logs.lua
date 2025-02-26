---@brief [[
--- Logs view for MCPHub UI
--- Shows server output and plugin logs
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")

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
    local self = View:new(ui, "logs") -- Create base view with name
    self.keymaps = {
        ['<TAB>'] = {
            action = function()
                view_state.current_tab = view_state.current_tab == "server" and "plugin" or "server"
                self:draw()
            end,
            desc = "Switch view"
        },
        ['a'] = {
            action = function()
                view_state.auto_scroll = not view_state.auto_scroll
                vim.notify(string.format("Auto-scroll %s", view_state.auto_scroll and "enabled" or "disabled"))
            end,
            desc = "Toggle auto-scroll"
        },
        ['c'] = {
            action = function()
                if view_state.current_tab == "server" then
                    State.output.stdout = {}
                    State.output.stderr = {}
                else
                    State.logs = {
                        debug = {},
                        info = {},
                        warn = {},
                        error = {}
                    }
                end
                self:draw()
            end,
            desc = "Clear logs"
        },
        ['r'] = {
            action = function()
                self:draw()
            end,
            desc = "Refresh view"
        }
    }
    return setmetatable(self, LogsView)
end

-- Format timestamp
local function format_time(timestamp)
    return os.date("%H:%M:%S", math.floor(timestamp / 1000))
end

--- Render tab selector
---@param width number Window width
---@return NuiLine[]
function LogsView:render_tabs(width)
    local lines = {}
    local tabs = {{
        id = "server",
        label = "Server Output"
    }, {
        id = "plugin",
        label = "Plugin Logs"
    }}

    local tab_line = NuiLine()
    for i, tab in ipairs(tabs) do
        if i > 1 then
            tab_line:append("  ")
        end

        local is_active = view_state.current_tab == tab.id
        tab_line:append("[")
        tab_line:append(is_active and "x" or " ", is_active and Text.highlights.success or Text.highlights.muted)
        tab_line:append("] " .. tab.label, is_active and Text.highlights.header or Text.highlights.muted)
    end

    table.insert(lines, Text.pad_line(tab_line))
    table.insert(lines, Text.divider(width))
    table.insert(lines, Text.empty_line())

    return lines
end

-- Parse and format JSON server output
local function format_server_log(data)
    local ok, parsed = pcall(vim.json.decode, data)
    if not ok then
        return data
    end

    local type_icons = {
        info = "● ",
        warn = "⚠ ",
        error = "✖ ",
        debug = "◆ "
    }

    local type_hl = {
        info = Text.highlights.info,
        warn = Text.highlights.warning,
        error = Text.highlights.error,
        debug = Text.highlights.muted
    }

    -- Build log line
    local line = NuiLine()
    line:append(type_icons[parsed.type] or "• ", type_hl[parsed.type])
    line:append(parsed.message, type_hl[parsed.type])

    -- Add extra context if available
    if parsed.data and not vim.tbl_isempty(parsed.data) then
        local details = vim.split(vim.inspect(parsed.data), "\n")
        if #details > 0 then
            line:append(" (", Text.highlights.muted)
            line:append(details[1]:gsub("^%s*{%s*(.-)%s*}%s*$", "%1"), Text.highlights.muted)
            line:append(")", Text.highlights.muted)
        end
    end

    return line
end

-- Render server output section
function LogsView:render_server_output()
    local lines = {}
    table.insert(lines, Text.section("Server Messages", {}, true)[1])

    -- Show stdout
    if #State.output.stdout > 0 then
        for _, entry in ipairs(State.output.stdout) do
            if entry.time and entry.data then
                local log_line =
                    NuiLine():append(string.format("[%s] ", format_time(entry.time)), Text.highlights.muted):append(
                        format_server_log(entry.data))
                table.insert(lines, Text.pad_line(log_line))
            end
        end
    else
        table.insert(lines, Text.pad_line("No output available", Text.highlights.muted))
    end

    -- Show stderr if any
    if #State.output.stderr > 0 then
        table.insert(lines, Text.empty_line())
        table.insert(lines, Text.section("Server Errors", {}, true)[1])
        for _, entry in ipairs(State.output.stderr) do
            if entry.time and entry.data then
                local error_line = NuiLine():append(string.format("[%s] ", format_time(entry.time)),
                    Text.highlights.muted):append("✖ ", Text.highlights.error):append(entry.data,
                    Text.highlights.error)
                table.insert(lines, Text.pad_line(error_line))
            end
        end
    end

    return lines
end

-- Render plugin logs section
function LogsView:render_plugin_logs()
    local lines = {}
    table.insert(lines, Text.section("Plugin Logs", {}, true)[1])

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
                    local log_line = NuiLine():append(string.format("[%s] ", format_time(entry.time)),
                        Text.highlights.muted):append(string.format("[%s] ", level:upper()), ({
                        error = Text.highlights.error,
                        warn = Text.highlights.warning,
                        info = Text.highlights.info,
                        debug = Text.highlights.muted
                    })[level])

                    if type(entry.message) == "table" then
                        if entry.message.formatted then
                            log_line:append(entry.message.formatted)
                        else
                            log_line:append(vim.inspect(entry.message.raw))
                        end
                    else
                        log_line:append(tostring(entry.message))
                    end

                    table.insert(lines, Text.pad_line(log_line))
                end
            end
        end
    end

    if not has_logs then
        table.insert(lines, Text.pad_line("No logs available", Text.highlights.muted))
    end

    return lines
end

function LogsView:render()
    -- Get base header
    local lines = self:render_header()
    local width = self:get_width()

    -- Add tab selection
    vim.list_extend(lines, self:render_tabs(width))

    -- Show content based on selected tab
    if view_state.current_tab == "server" then
        vim.list_extend(lines, self:render_server_output())
    else
        vim.list_extend(lines, self:render_plugin_logs())
    end

    return lines
end

return LogsView

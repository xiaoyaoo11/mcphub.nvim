---@brief [[
--- Servers view for MCPHub UI
--- Shows detailed server information and management
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local renderer = require("mcphub.utils.renderer")
local highlights = require("mcphub.utils.highlights")

---@class ServersView
---@field super View
---@field cursor_highlight number|nil Extmark ID for current highlight
---@field hover_ns number Namespace for highlights
---@field server_sections table<string, {start_line: number, end_line: number, tools: {name: string, line: number}[]}>
---@field execution_state { active: boolean, server_name: string|nil, tool_name: string|nil, tool_info: table|nil }
local ServersView = setmetatable({}, {
    __index = View
})
ServersView.__index = ServersView

function ServersView:new(ui)
    local self = View:new(ui, "servers") -- Create base view with name
    self = setmetatable(self, ServersView)

    -- Create namespace for highlights
    self.hover_ns = vim.api.nvim_create_namespace("MCPHubServersHover")
    self.cursor_highlight = nil
    self.server_sections = {}
    self.execution_state = {
        active = false,
        server_name = nil,
        tool_name = nil,
        tool_info = nil
    }

    return self
end

--- Get server and tool info for a given line number
---@param line_nr number
---@return string|nil server_name, string|nil tool_name
function ServersView:get_line_info(line_nr)
    for server_name, section in pairs(self.server_sections) do
        if line_nr >= section.start_line and line_nr <= section.end_line then
            -- Check if line is a tool line
            for _, tool in ipairs(section.tools) do
                if tool.line == line_nr then
                    return server_name, tool.name
                end
            end
            return server_name, nil
        end
    end
    return nil, nil
end

--- Handle cursor movement
---@private
function ServersView:handle_cursor_move()
    -- Don't handle cursor moves in execution mode
    if self.execution_state.active then
        return
    end

    -- Clear previous highlight if any
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Check if line contains tool using our mapping
    local server_name, tool_name = self:get_line_info(line)
    if tool_name then
        -- Add highlight and virtual text
        self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
            line_hl_group = highlights.groups.active_item,
            virt_text = {{"Press <CR> to execute", highlights.groups.muted}},
            virt_text_pos = "eol"
        })
    end
end

function ServersView:get_tool_info(server_name, tool_name)
    local server = nil
    for _, s in ipairs(State.server_state.servers or {}) do
        if s.name == server_name then
            server = s
            break
        end
    end

    if server and server.capabilities then
        for _, tool in ipairs(server.capabilities.tools) do
            if tool.name == tool_name then
                return tool
            end
        end
    end
    return nil
end

function ServersView:enter_execution_mode(server_name, tool_name)
    self.execution_state = {
        active = true,
        server_name = server_name,
        tool_name = tool_name,
        tool_info = self:get_tool_info(server_name, tool_name)
    }
end

function ServersView:exit_execution_mode()
    self.execution_state = {
        active = false,
        server_name = nil,
        tool_name = nil,
        tool_info = nil
    }
end

function ServersView:render_breadcrumb()
    if not self.execution_state.active then
        return {}
    end

    local breadcrumb = NuiLine():append(self.execution_state.server_name, Text.highlights.title):append(" > ",
        Text.highlights.muted):append(" " .. self.execution_state.tool_name .. " ", Text.highlights.header)

    return {Text.pad_line(breadcrumb)}
end

function ServersView:on_enter()
    View.on_enter(self) -- Call parent method

    -- Set up cursor movement tracking
    local group = vim.api.nvim_create_augroup("MCPHubServersCursor", {
        clear = true
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = self.ui.buffer,
        callback = function()
            self:handle_cursor_move()
        end
    })

    -- Add <CR> mapping for tool execution
    self:add_keymap("<CR>", function()
        if self.execution_state.active then
            return -- Ignore in execution mode for now (will handle in phase 3)
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = cursor[1]

        -- Get tool info from our mapping
        local server_name, tool_name = self:get_line_info(line)
        if server_name and tool_name then
            self:enter_execution_mode(server_name, tool_name)
            self:draw() -- Redraw in execution mode
        end
    end, "Execute tool/resource")

    -- Add escape mapping to exit execution mode
    self:add_keymap("<Esc>", function()
        if self.execution_state.active then
            self:exit_execution_mode()
            self:draw()
        end
    end, "Exit tool execution mode")
end

function ServersView:on_leave()
    -- Clear highlight when leaving view
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- -- Exit execution mode if active
    -- if self.execution_state.active then
    --     self:exit_execution_mode()
    -- end

    View.on_leave(self) -- Call parent method
end

-- Helper to format duration
local function format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Render server information
---@param server table Server data
---@param line_offset number Current line number offset
---@return NuiLine[] lines, number new_offset
local function render_server(server, line_offset)
    local lines = {}

    local current_line = line_offset + 1
    -- Server header with status icon
    local status_icons = {
        connected = "● ",
        connecting = "◉ ",
        disconnected = "○ "
    }
    local status_hl = {
        connected = Text.highlights.success,
        connecting = Text.highlights.info,
        disconnected = Text.highlights.warning
    }

    -- Server title line
    local title = NuiLine():append("╭─ ", Text.highlights.muted):append(status_icons[server.status] or "⚠ ",
        status_hl[server.status] or Text.highlights.error):append(server.name, Text.highlights.header):append(" (",
        Text.highlights.muted):append(server.status, status_hl[server.status] or Text.highlights.error):append(")",
        Text.highlights.muted)
    table.insert(lines, Text.pad_line(title))

    -- Server details
    if server.uptime then
        local uptime = NuiLine():append("│ ", Text.highlights.muted):append("Uptime: ", Text.highlights.muted):append(
            format_uptime(server.uptime), Text.highlights.info)
        table.insert(lines, Text.pad_line(uptime))
    end
    if server.lastStarted then
        local started = NuiLine():append("│ ", Text.highlights.muted):append("Started: ", Text.highlights.muted)
            :append(server.lastStarted, Text.highlights.info)
        table.insert(lines, Text.pad_line(started))
    end

    -- Capabilities
    if server.capabilities then
        -- Tools
        if #server.capabilities.tools > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(NuiLine():append("│ Tools:", Text.highlights.header)))

            for _, tool in ipairs(server.capabilities.tools) do
                -- Tool name
                local tool_line = NuiLine():append("│  • ", Text.highlights.muted):append(tool.name,
                    Text.highlights.success)
                table.insert(lines, Text.pad_line(tool_line))

                -- Track tool line number at the actual buffer position
                tool._line_nr = line_offset + #lines

                -- Tool description
                if tool.description then
                    for _, desc_line in ipairs(Text.multiline(tool.description)) do
                        local desc = NuiLine():append("│    ", Text.highlights.muted):append(desc_line,
                            Text.highlights.muted)
                        table.insert(lines, Text.pad_line(desc))
                    end
                end
            end
        end

        -- Resources
        if #server.capabilities.resources > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(NuiLine():append("│ Resources:", Text.highlights.header)))
            for _, resource in ipairs(server.capabilities.resources) do
                local res_line = NuiLine():append("│  • ", Text.highlights.muted):append(resource.name,
                    Text.highlights.success):append(" (", Text.highlights.muted):append(resource.mimeType,
                    Text.highlights.info):append(")", Text.highlights.muted)
                table.insert(lines, Text.pad_line(res_line))
            end
        end
    end

    -- Server footer
    table.insert(lines, Text.pad_line(NuiLine():append("╰─", Text.highlights.muted)))
    table.insert(lines, Text.empty_line())

    return lines, line_offset + #lines
end

function ServersView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end

    -- Get base header (with/without extra line based on mode)
    local lines = self:render_header(not self.execution_state.active)

    if self.execution_state.active then
        -- Execution mode view
        vim.list_extend(lines, self:render_breadcrumb())
        vim.list_extend(lines, {self:divider()})

        -- Tool info section
        if self.execution_state.tool_info then
            -- Description
            local desc = self.execution_state.tool_info.description or "No description available"
            vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(desc, Text.highlights.info)))

            -- Schema info (placeholder for Phase 3)
            if self.execution_state.tool_info.inputSchema then
                -- Basic schema display
                table.insert(lines, Text.empty_line())
                table.insert(lines, Text.pad_line(NuiLine():append(" Input Parameters: ", Text.highlights.header)))
                -- Schema details will be enhanced in Phase 3
            end
        end
        return lines
    end

    local width = self:get_width()
    -- Reset server sections for new render
    self.server_sections = {}

    -- Add servers section based on state
    if State.server_state.status == "connected" then
        if State.server_state.servers and #State.server_state.servers > 0 then
            local current_line = #lines

            for _, server in ipairs(State.server_state.servers) do
                -- Track server section
                local section = {
                    start_line = current_line + 1,
                    tools = {}
                }

                -- Store tool line numbers during render
                local new_lines
                new_lines, current_line = render_server(server, current_line)
                vim.list_extend(lines, new_lines)

                -- Store tool line numbers
                if server.capabilities and server.capabilities.tools then
                    for _, tool in ipairs(server.capabilities.tools) do
                        if tool._line_nr then
                            table.insert(section.tools, {
                                name = tool.name,
                                line = tool._line_nr
                            })
                            tool._line_nr = nil -- Clean up temp property
                        end
                    end
                end

                section.end_line = current_line
                self.server_sections[server.name] = section
            end
        else
            table.insert(lines, Text.align_text("No servers connected", width, "center", Text.highlights.muted))
        end
        vim.list_extend(lines, renderer.render_hub_errors(State.errors.server))
    else
        -- Show offline state
        table.insert(lines,
            Text.align_text(
                State.server_state.status == "connecting" and "Connecting to server..." or "Server disconnected", width,
                "center", State.server_state.status == "connecting" and Text.highlights.info or Text.highlights.warning))

        -- Show error if disconnected
        if State.server_state.status == "disconnected" and #State.errors.server > 0 then
            local err = State.errors.server[#State.errors.server]
            local error_line = NuiLine():append("• ", Text.highlights.error)
                :append(err.message, Text.highlights.error)
            table.insert(lines, Text.empty_line())
            table.insert(lines, Text.pad_line(error_line))
        end
    end

    return lines
end

return ServersView

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
local Utils = require("mcphub.ui.views.servers_utils")

---@class ServersView
---@field super View
---@field cursor_highlight number|nil Extmark ID for current highlight
---@field hover_ns number Namespace for highlights
---@field server_sections table<string, {start_line: number, end_line: number, tools: {name: string, line: number}[]}>
---@field execution_state { active: boolean, server_name: string|nil, tool_name: string|nil, tool_info: table|nil, params: { values: table<string, string>, errors: table<string, string>, param_lines: table<number, string>, submit_line: number|nil, submit_error: string|nil, result: table|nil, is_executing: boolean }|nil }
---@field cursor_group number|nil Cursor movement tracking group
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
        tool_info = nil,
        params = nil
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
    -- Clear previous highlight if any
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    if self.execution_state.active then
        -- In execution mode, highlight input lines and submit
        if self.execution_state.params.param_lines[line] then
            self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
                line_hl_group = highlights.groups.active_item,
                virt_text = {{"Press <CR> to edit", highlights.groups.muted}},
                virt_text_pos = "eol"
            })
        elseif line == self.execution_state.params.submit_line and not self.execution_state.params.is_executing then
            self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
                line_hl_group = highlights.groups.active_item,
                virt_text = {{"Press <CR> to submit", highlights.groups.muted}},
                virt_text_pos = "eol"
            })
        end
        return
    end

    -- Not in execution mode - highlight tools
    local server_name, tool_name = self:get_line_info(line)
    if tool_name then
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
        tool_info = self:get_tool_info(server_name, tool_name),
        params = {
            values = {},
            errors = {},
            param_lines = {},
            submit_line = nil,
            submit_error = nil,
            result = nil,
            is_executing = false
        }
    }
    self:setup_active_mode()
end

function ServersView:exit_execution_mode()
    self.execution_state = {
        active = false,
        server_name = nil,
        tool_name = nil,
        tool_info = nil,
        params = nil
    }
    self:setup_active_mode()
end

function ServersView:handle_param_action()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    if line == self.execution_state.params.submit_line then
        -- Check if already executing
        if self.execution_state.params.is_executing then
            vim.notify("Tool is already executing", vim.log.levels.WARN)
            return
        end

        -- On submit button
        local ok, err, errors = Utils.validate_all_params(self.execution_state.tool_info,
            self.execution_state.params.values)
        if not ok then
            self.execution_state.params.submit_error = err
            self.execution_state.params.errors = errors
            self:draw()
            return
        end

        -- Convert all values to their proper types
        local converted_values = {}

        for name, value in pairs(self.execution_state.params.values) do
            local schema = self.execution_state.tool_info.inputSchema.properties[name]
            if schema then
                converted_values[name] = Utils.convert_param(value, schema)
            end
        end

        -- Set executing state
        self.execution_state.params.is_executing = true
        self:draw() -- Redraw to show loading state

        -- Execute tool with converted values
        if State.hub_instance then
            State.hub_instance:call_tool(self.execution_state.server_name, self.execution_state.tool_name,
                converted_values, {
                    return_text = true,
                    callback = function(response, err)
                        self.execution_state.params.is_executing = false -- Reset executing state
                        if err then
                            vim.notify("Tool execution failed: " .. err, vim.log.levels.ERROR)
                            self.execution_state.params.submit_error = err
                        else
                            vim.notify("Tool executed successfully", vim.log.levels.INFO)
                            self.execution_state.params.result = response
                            self.execution_state.params.submit_error = nil
                        end
                        self:draw()
                    end
                })
        end
        return
    end

    -- Check if line is a parameter input
    local param_name = self.execution_state.params.param_lines[line]
    if not param_name then
        return
    end

    -- Get parameter schema
    local param_schema
    if self.execution_state.tool_info and self.execution_state.tool_info.inputSchema and
        self.execution_state.tool_info.inputSchema.properties then
        param_schema = self.execution_state.tool_info.inputSchema.properties[param_name]
    end

    if not param_schema then
        vim.notify("Invalid parameter schema", vim.log.levels.ERROR)
        return
    end

    -- Show input prompt for parameter with type information
    vim.ui.input({
        prompt = string.format("%s (%s): ", param_name, Utils.format_param_type(param_schema)),
        default = self.execution_state.params.values[param_name] or ""
    }, function(input)
        if input then
            -- Validate input
            local ok, err = Utils.validate_param(input, param_schema)
            if not ok then
                self.execution_state.params.errors[param_name] = err
            else
                -- Update value
                self.execution_state.params.values[param_name] = input
                -- Clear any previous error
                self.execution_state.params.errors[param_name] = nil
            end
            self:draw()
        end
    end)
end

function ServersView:render_breadcrumb()
    if not self.execution_state.active then
        return {}
    end

    local breadcrumb = NuiLine():append(self.execution_state.server_name, Text.highlights.muted):append(" > ",
        Text.highlights.muted):append(" " .. self.execution_state.tool_name .. " ", Text.highlights.title)

    return {Text.pad_line(breadcrumb)}
end

function ServersView:setup_active_mode()
    if self.execution_state.active then
        self.keymaps = {
            ["<CR>"] = {
                action = function()
                    self:handle_param_action()
                end,
                desc = "Edit/Submit"
            },
            ["<Esc>"] = {
                action = function()
                    self:exit_execution_mode()
                    self:draw()
                end,
                desc = "Back"
            }
        }
    else
        self.keymaps = {
            ["<CR>"] = {
                action = function()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local line = cursor[1]

                    -- Get tool info from our mapping
                    local server_name, tool_name = self:get_line_info(line)
                    if server_name and tool_name then
                        self:enter_execution_mode(server_name, tool_name)
                        self:draw() -- Redraw in execution mode
                    end
                end,
                desc = "Execute tool/resource"
            }
        }
    end
    self:apply_keymaps()
end

function ServersView:on_enter()
    View.on_enter(self) -- Call parent method

    -- Set up cursor movement tracking
    self.cursor_group = vim.api.nvim_create_augroup("MCPHubServersCursor", {
        clear = true
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = self.cursor_group,
        buffer = self.ui.buffer,
        callback = function()
            self:handle_cursor_move()
        end
    })

    self:setup_active_mode()
end

function ServersView:on_leave()
    -- Clear highlight when leaving view
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Clean up cursor tracking
    if self.cursor_group then
        vim.api.nvim_del_augroup_by_name("MCPHubServersCursor")
        self.cursor_group = nil
    end

    View.on_leave(self) -- Call parent method
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
            vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(desc, Text.highlights.muted)))
            table.insert(lines, Text.empty_line())

            -- Parameters form with line tracking
            local form_lines, param_lines, submit_line = Utils.render_params_form(self.execution_state.tool_info,
                self.execution_state.params, self)
            vim.list_extend(lines, form_lines)

            -- Update line tracking in execution state
            self.execution_state.params.param_lines = {}
            for line_nr, param_name in pairs(param_lines) do
                self.execution_state.params.param_lines[#lines - #form_lines + line_nr] = param_name
            end
            self.execution_state.params.submit_line = #lines - #form_lines + submit_line
        end
        return lines
    end

    -- Server listing view
    local width = self:get_width()
    self.server_sections = {} -- Reset sections

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
                new_lines, current_line = Utils.render_server(server, current_line)
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

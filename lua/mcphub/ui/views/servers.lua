---@brief [[
--- Servers view for MCPHub UI
--- Shows detailed server information and management
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local renderer = require("mcphub.utils.renderer")
local Capabilities = require("mcphub.ui.capabilities")
local utils = require("mcphub.utils")

---@class ServersView
---@field super View
---@field cursor_highlight number|nil Extmark ID for current highlight
---@field hover_ns number Namespace for highlights
---@field server_sections table<string, {start_line: number, end_line: number, tools: {name: string, line: number, info: table}[], resources: {name: string, line: number, info: table}[]}>
---@field active_capability CapabilityHandler|nil Currently active capability
---@field cursor_group number|nil Cursor movement tracking group
---@field cursor_positions {browse_mode: number[]|nil, capability_line: number[]|nil} Cursor positions for different modes
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
    self.active_capability = nil
    self.cursor_positions = {
        browse_mode = nil, -- Will store [line, col]
        capability_line = nil -- Will store [line, col]
    }

    return self
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

    if self.active_capability and self.active_capability.handle_cursor_move then
        self.active_capability:handle_cursor_move(self, line)
        return
    end

    -- Highlight available capabilities
    local _, cap_type = self:get_line_info(line)
    if cap_type then
        self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
            line_hl_group = Text.highlights.active_item,
            virt_text = {{"Press <CR> to open", Text.highlights.muted}},
            virt_text_pos = "eol"
        })
    end
end

--- Get capability info for a given line number
---@param line_nr number
---@return string|nil server_name, string|nil capability_type, table|nil capability_info
function ServersView:get_line_info(line_nr)
    for server_name, section in pairs(self.server_sections) do
        if line_nr >= section.start_line and line_nr <= section.end_line then
            -- Check tools
            for _, tool in ipairs(section.tools) do
                if tool.line == line_nr then
                    return server_name, "tool", tool.info
                end
            end
            -- Check resources
            for _, resource in ipairs(section.resources) do
                if resource.line == line_nr then
                    return server_name, "resource", resource.info
                end
            end
            return server_name, nil, nil
        end
    end
    return nil, nil, nil
end

function ServersView:handle_capability_action()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)

    if self.active_capability then
        -- Let active capability handle the action
        if self.active_capability.handle_action then
            self.active_capability:handle_action(cursor[1])
        end
        return
    end

    -- Check if we're activating a new capability
    local server_name, cap_type, cap_info = self:get_line_info(cursor[1])
    if cap_type then
        -- Store browse mode position before entering capability
        self.cursor_positions.browse_mode = cursor

        -- Create new capability handler
        self.active_capability = Capabilities.create_handler(cap_type, server_name, cap_info, self)
        self:setup_active_mode()
        self:draw()

        -- Move to capability's preferred position
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            vim.api.nvim_win_set_cursor(0, cap_pos)
        end
    end
end

function ServersView:setup_active_mode()
    if self.active_capability then
        self.keymaps = {
            ["<CR>"] = {
                action = function()
                    self:handle_capability_action()
                end,
                desc = "Execute/Submit"
            },
            ["<Esc>"] = {
                action = function()
                    -- Store capability line before exiting
                    self.cursor_positions.capability_line = vim.api.nvim_win_get_cursor(0)

                    -- Clear active capability
                    self.active_capability = nil

                    -- Setup browse mode and redraw
                    self:setup_active_mode()
                    self:draw()

                    -- Restore to last browse mode position
                    if self.cursor_positions.browse_mode then
                        vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
                    end
                end,
                desc = "Back"
            }
        }
    else
        self.keymaps = {
            ["<CR>"] = {
                action = function()
                    self:handle_capability_action()
                end,
                desc = "Open capability"
            }
        }
    end
    self:apply_keymaps()
end

function ServersView:before_enter()
    View.before_enter(self)
    self:setup_active_mode()
end

function ServersView:after_enter()
    View.after_enter(self)

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

    -- Restore appropriate cursor position
    if self.active_capability then
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            vim.api.nvim_win_set_cursor(0, cap_pos)
        end
    else
        -- In browse mode, restore last browse position with column
        if self.cursor_positions.browse_mode then
            vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
        end
    end
end

function ServersView:before_leave()
    -- Store appropriate position based on current mode
    if self.active_capability then
        -- In capability mode, store full position
        self.cursor_positions.capability_line = vim.api.nvim_win_get_cursor(0)
    else
        -- In browse mode, store full position
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)
    end

    View.before_leave(self)
end

function ServersView:after_leave()
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

    View.after_leave(self)
end

function ServersView:render_breadcrumb()
    if not self.active_capability then
        return {}
    end

    local breadcrumb = NuiLine():append(self.active_capability.server_name, Text.highlights.muted):append(" > ",
        Text.highlights.muted):append(" " .. self.active_capability.info.name .. " ", Text.highlights.title)

    return {Text.pad_line(breadcrumb)}
end

function ServersView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end

    -- Get base header (with/without extra line based on mode)
    local lines = self:render_header(not self.active_capability)

    if self.active_capability then
        -- Active capability view
        vim.list_extend(lines, self:render_breadcrumb())
        vim.list_extend(lines, {self:divider()})

        -- Let capability render its content
        vim.list_extend(lines, self.active_capability:render(#lines))
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
                    tools = {},
                    resources = {}
                }

                -- Store tool line numbers during render
                local new_lines
                new_lines, current_line = self:render_server_details(server, current_line, section)
                vim.list_extend(lines, new_lines)

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

--- Render server details with tools and resources
---@param server table Server data
---@param line_offset number Current line number offset
---@param section table Section info to update with capabilities
---@return NuiLine[] lines, number new_offset
function ServersView:render_server_details(server, line_offset, section)
    local lines = {}

    -- Server header
    local title = NuiLine():append("╭─ ", Text.highlights.muted):append(" " .. server.name .. " ",
        Text.highlights.header_btn)
    table.insert(lines, Text.pad_line(title))

    -- Server details
    if server.uptime then
        local uptime = NuiLine():append("│ ", Text.highlights.muted):append("Uptime: ", Text.highlights.muted):append(
            utils.format_uptime(server.uptime), Text.highlights.info)
        table.insert(lines, Text.pad_line(uptime))
    end

    -- Capabilities
    if server.capabilities then
        -- Tools
        if #server.capabilities.tools > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Tools: ", Text.highlights.header)))

            for _, tool in ipairs(server.capabilities.tools) do
                -- Tool name
                local tool_line = NuiLine():append("│  • ", Text.highlights.muted):append(tool.name,
                    Text.highlights.success)
                table.insert(lines, Text.pad_line(tool_line))

                -- Track tool line number for interaction
                local line_nr = line_offset + #lines
                table.insert(section.tools, {
                    name = tool.name,
                    line = line_nr,
                    info = tool
                })

                -- Tool description
                if tool.description then
                    for _, desc_line in ipairs(Text.multiline(tool.description, Text.highlights.muted)) do
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
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Resources: ", Text.highlights.header)))

            for _, resource in ipairs(server.capabilities.resources) do
                local res_line = NuiLine():append("│  • ", Text.highlights.muted):append(resource.name,
                    Text.highlights.success):append(" (", Text.highlights.muted):append(resource.mimeType,
                    Text.highlights.info):append(")", Text.highlights.muted)
                table.insert(lines, Text.pad_line(res_line))

                -- Track resource line number for interaction
                local line_nr = line_offset + #lines
                table.insert(section.resources, {
                    name = resource.name,
                    line = line_nr,
                    info = resource
                })

                -- Resource description if any
                if resource.description then
                    for _, desc_line in ipairs(Text.multiline(resource.description, Text.highlights.muted)) do
                        local desc = NuiLine():append("│    ", Text.highlights.muted):append(desc_line,
                            Text.highlights.muted)
                        table.insert(lines, Text.pad_line(desc))
                    end
                end
            end
        end
    end

    -- Server footer
    table.insert(lines, Text.pad_line(NuiLine():append("╰─", Text.highlights.muted)))
    table.insert(lines, Text.empty_line())

    return lines, line_offset + #lines
end

return ServersView

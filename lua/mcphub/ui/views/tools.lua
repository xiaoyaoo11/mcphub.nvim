---@brief [[
--- Tools view for MCPHub UI
--- Shows available tools and handles execution
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")

---@class ToolsView
---@field super View
local ToolsView = setmetatable({}, {
    __index = View
})
ToolsView.__index = ToolsView

---@class ToolsViewState
---@field selected_server string|nil Currently selected server
---@field selected_tool string|nil Currently selected tool
local view_state = {
    selected_server = nil,
    selected_tool = nil
}

function ToolsView:new(ui)
    local instance = View:new(ui) -- Create base view
    return setmetatable(instance, ToolsView)
end

--- Get currently available servers with tools
local function get_available_servers()
    local servers = {}
    if State.server_state.status == "connected" and State.server_state.servers then
        for _, server in ipairs(State.server_state.servers) do
            if server.capabilities and server.capabilities.tools and #server.capabilities.tools > 0 then
                table.insert(servers, server)
            end
        end
    end
    return servers
end

--- Find tool in server by name
local function find_tool(server, tool_name)
    for _, tool in ipairs(server.capabilities.tools) do
        if tool.name == tool_name then
            return tool
        end
    end
    return nil
end

--- Render tool details
local function render_tool_info(tool, lines)
    table.insert(lines, "Tool Details:")
    table.insert(lines, string.format("  Name: %s", tool.name))
    if tool.description then
        table.insert(lines, "  Description:")
        for _, line in ipairs(vim.split(tool.description, "\n")) do
            table.insert(lines, string.format("    %s", line))
        end
    end

    -- Show input schema if available
    if tool.inputSchema then
        table.insert(lines, "  Parameters:")
        for name, schema in pairs(tool.inputSchema) do
            local type_info = schema.type or "any"
            if schema.enum then
                type_info = table.concat(schema.enum, "|")
            end
            table.insert(lines, string.format("    %s (%s)", name, type_info))
            if schema.description then
                table.insert(lines, string.format("      %s", schema.description))
            end
        end
    end
end

function ToolsView:render()
    -- Get base header
    local lines = self:render_header()

    -- Add tools section
    if State.setup_state == "failed" then
        table.insert(lines, "Setup Failed:")
        for _, err in ipairs(State.setup_errors) do
            table.insert(lines, string.format("• %s", err.message))
        end
    elseif State.setup_state == "in_progress" then
        table.insert(lines, "Setting up MCPHub...")
    else
        if State.server_state.status == "connected" then
            local servers = get_available_servers()
            if #servers > 0 then
                -- Show server selection if no server selected
                if not view_state.selected_server then
                    table.insert(lines, "Available Servers:")
                    for i, server in ipairs(servers) do
                        table.insert(lines,
                            string.format("%d. %s (%d tools)", i, server.name, #server.capabilities.tools))
                    end
                    table.insert(lines, "")
                    table.insert(lines, "Press 1-9 to select a server")
                else
                    -- Find selected server
                    local selected = nil
                    for _, server in ipairs(servers) do
                        if server.name == view_state.selected_server then
                            selected = server
                            break
                        end
                    end

                    if selected then
                        -- Show server header
                        table.insert(lines, string.format("Server: %s", selected.name))
                        table.insert(lines, string.format("Status: %s", selected.status))
                        table.insert(lines, "")

                        -- Show tool listing or details
                        if not view_state.selected_tool then
                            table.insert(lines, "Available Tools:")
                            for i, tool in ipairs(selected.capabilities.tools) do
                                table.insert(lines, string.format("%d. %s", i, tool.name))
                                if tool.description then
                                    -- Show first line of description
                                    local desc = vim.split(tool.description, "\n")[1]
                                    if desc then
                                        table.insert(lines, string.format("   %s", desc))
                                    end
                                end
                            end
                            table.insert(lines, "")
                            table.insert(lines, "Press 1-9 to select a tool")
                        else
                            -- Show tool details
                            local tool = find_tool(selected, view_state.selected_tool)
                            if tool then
                                render_tool_info(tool, lines)
                            else
                                table.insert(lines, "Tool no longer available")
                            end
                        end
                    else
                        table.insert(lines, "Selected server no longer available")
                    end
                end
            else
                table.insert(lines, "No servers with tools available")
            end
        else
            table.insert(lines, "Server disconnected")
            if #State.server_state.errors > 0 then
                table.insert(lines, "")
                table.insert(lines, "Server Errors:")
                local err = State.server_state.errors[#State.server_state.errors]
                table.insert(lines, string.format("• %s", err.message))
            end
        end
    end

    -- Add help text
    table.insert(lines, "")
    table.insert(lines, "Press:")
    if view_state.selected_tool then
        table.insert(lines, " <CR> - Execute tool    <BS> - Back to tools")
    elseif view_state.selected_server then
        table.insert(lines, " <BS> - Back to servers   r - Refresh")
    else
        table.insert(lines, " r - Refresh")
    end
    table.insert(lines, " <ESC> - Return to main view  q - Close window")

    return lines
end

function ToolsView:setup_keymaps()
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

    -- Back navigation
    map('<BS>', function()
        if view_state.selected_tool then
            view_state.selected_tool = nil
        else
            view_state.selected_server = nil
        end
        self:render()
    end, "Go back")

    -- Refresh
    map('r', function()
        if State.hub_instance then
            State.hub_instance:get_health()
        end
    end, "Refresh servers")

    -- Selection keys
    for i = 1, 9 do
        map(tostring(i), function()
            local servers = get_available_servers()
            if not view_state.selected_server then
                -- Select server
                if i <= #servers then
                    view_state.selected_server = servers[i].name
                    self:render()
                end
            elseif not view_state.selected_tool then
                -- Select tool
                local server = nil
                for _, s in ipairs(servers) do
                    if s.name == view_state.selected_server then
                        server = s
                        break
                    end
                end
                if server and i <= #server.capabilities.tools then
                    view_state.selected_tool = server.capabilities.tools[i].name
                    self:render()
                end
            end
        end, "Select item")
    end
end

function ToolsView:on_enter()
    -- Reset selection state
    view_state.selected_server = nil
    view_state.selected_tool = nil
end

return ToolsView

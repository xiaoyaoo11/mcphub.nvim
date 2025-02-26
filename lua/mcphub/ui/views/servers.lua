---@brief [[
--- Servers view for MCPHub UI
--- Shows detailed server information and management
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")

---@class ServersView
---@field super View
local ServersView = setmetatable({}, {
    __index = View
})
ServersView.__index = ServersView

function ServersView:new(ui)
    local self = View:new(ui, "servers") -- Create base view with name
    self.keymaps = {
        ['r'] = {
            action = function()
                if State.setup_state == "completed" and State.hub_instance then
                    State.hub_instance:get_health()
                end
            end,
            desc = "Refresh servers"
        }
    }

    return setmetatable(self, ServersView)
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
---@return NuiLine[] lines
local function render_server(server)
    local lines = {}

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

    return lines
end

function ServersView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end

    -- Get base header
    local lines = self:render_header()
    local width = self:get_width()
    -- Add servers section based on state
    if State.server_state.status == "connected" then
        if State.server_state.servers and #State.server_state.servers > 0 then
            for _, server in ipairs(State.server_state.servers) do
                vim.list_extend(lines, render_server(server))
            end
        else
            table.insert(lines, Text.align_text("No servers connected", width, "center", Text.highlights.muted))
        end

        -- Show recent errors if any
        if #State.errors.server > 0 then
            table.insert(lines, Text.empty_line())
            table.insert(lines, Text.section("Recent Issues", {}, true)[1])

            -- Show last 3 errors
            for i = #State.errors.server, math.max(1, #State.errors.server - 2), -1 do
                local err = State.errors.server[i]
                local error_line = NuiLine():append("• ", Text.highlights.error):append(err.message,
                    Text.highlights.error)
                table.insert(lines, Text.pad_line(error_line))

                -- Add error details if any
                if err.details then
                    local details = vim.split(vim.inspect(err.details), "\n")
                    for _, detail in ipairs(details) do
                        local detail_line = NuiLine():append("  "):append(detail, Text.highlights.muted)
                        table.insert(lines, Text.pad_line(detail_line))
                    end
                end
            end
        end
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

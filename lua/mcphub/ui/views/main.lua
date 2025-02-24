---@brief [[
--- Main dashboard view for MCPHub
--- Shows server status and connected servers
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")

---@class MainView
---@field super View
local MainView = setmetatable({}, {
    __index = View
})
MainView.__index = MainView

function MainView:new(ui)
    local instance = View:new(ui) -- Create base view
    return setmetatable(instance, MainView)
end

--- Format timestamp relative to now
---@param timestamp number Unix timestamp
---@return string
local function format_relative_time(timestamp)
    local now = vim.loop.now()
    local diff = now - timestamp

    if diff < 60000 then -- Less than a minute
        return "just now"
    elseif diff < 3600000 then -- Less than an hour
        local mins = math.floor(diff / 60000)
        return string.format("%d min%s ago", mins, mins > 1 and "s" or "")
    elseif diff < 86400000 then -- Less than a day
        local hours = math.floor(diff / 3600000)
        return string.format("%d hour%s ago", hours, hours > 1 and "s" or "")
    else -- Days
        local days = math.floor(diff / 86400000)
        return string.format("%d day%s ago", days, days > 1 and "s" or "")
    end
end

function MainView:render()
    local lines = {}
    local width = self:get_width()

    -- Logo
    local logo = Text.render_logo(width)
    for _, line in ipairs(logo) do
        table.insert(lines, line)
    end

    -- Add divider
    local divider = Text.align_text(string.rep("═", math.min(width - 4, 60)), width, "center", Text.highlights.muted)
    table.insert(lines, NuiLine())
    table.insert(lines, divider)
    table.insert(lines, NuiLine())

    if true then
        return lines
    end

    -- Show setup/server state
    if State.setup_state == "failed" then
        table.insert(lines, NuiLine():append("Setup Failed:", Text.highlights.error))
        for _, err in ipairs(State.setup_errors) do
            local line = NuiLine()
            line:append("• ", Text.highlights.error)
            line:append(err.message, Text.highlights.error)
            if err.details then
                line:append("\n  ")
                line:append("Details: ", Text.highlights.muted)
                line:append(vim.inspect(err.details), Text.highlights.muted)
            end
            table.insert(lines, line)
        end
    elseif State.setup_state == "in_progress" then
        table.insert(lines, Text.align_text("Setting up MCPHub...", width, "center", Text.highlights.info))
    else
        -- Show server state
        if State.server_state.status == "connected" then
            -- Status line
            local status_line = NuiLine()
            status_line:append("Server Status: ", Text.highlights.info)
            status_line:append("Connected", Text.highlights.success)
            table.insert(lines, Text.align_text(status_line:content(), width, "center"))

            if State.server_state.pid then
                table.insert(lines,
                    Text.align_text(string.format("Process ID: %d", State.server_state.pid), width, "center"))
            end
            if State.server_state.started_at then
                table.insert(lines, Text.align_text(
                    string.format("Started: %s", format_relative_time(State.server_state.started_at)), width, "center"))
            end

            -- Show servers if any
            if State.server_state.servers and #State.server_state.servers > 0 then
                -- Add section divider
                table.insert(lines, NuiLine())
                table.insert(lines, divider)
                table.insert(lines, NuiLine())
                table.insert(lines, NuiLine():append("Connected Servers:", Text.highlights.header))

                for _, server in ipairs(State.server_state.servers) do
                    -- Server name line
                    local server_line = NuiLine()
                    server_line:append("• ")
                    server_line:append(server.name .. " ", Text.highlights.success)
                    server_line:append("(" .. server.status .. ")", Text.highlights.info)
                    table.insert(lines, server_line)

                    -- Server capabilities line
                    if server.capabilities then
                        local cap_line = NuiLine()
                        cap_line:append("  └─ ")
                        cap_line:append("Tools: ", Text.highlights.muted)
                        cap_line:append(tostring(#server.capabilities.tools), Text.highlights.info)
                        cap_line:append(", ", Text.highlights.muted)
                        cap_line:append("Resources: ", Text.highlights.muted)
                        cap_line:append(tostring(#server.capabilities.resources), Text.highlights.info)
                        table.insert(lines, cap_line)
                    end
                end
            else
                table.insert(lines, NuiLine())
                table.insert(lines, Text.align_text("No servers connected", width, "center", Text.highlights.muted))
            end

            -- Show recent errors if any
            if #State.server_state.errors > 0 then
                -- Add section divider
                table.insert(lines, NuiLine())
                table.insert(lines, divider)
                table.insert(lines, NuiLine())
                table.insert(lines, NuiLine():append("Recent Server Issues:", Text.highlights.warning))
                -- Show last 3 errors
                for i = #State.server_state.errors, math.max(1, #State.server_state.errors - 2), -1 do
                    local err = State.server_state.errors[i]
                    local line = NuiLine()
                    line:append("• ", Text.highlights.error)
                    line:append(err.message, Text.highlights.error)
                    if err.time then
                        line:append(" (", Text.highlights.muted)
                        line:append(format_relative_time(err.time), Text.highlights.muted)
                        line:append(")", Text.highlights.muted)
                    end
                    table.insert(lines, line)
                end
            end
        elseif State.server_state.status == "connecting" then
            table.insert(lines, Text.align_text("Server Status: Connecting...", width, "center", Text.highlights.info))
        else
            table.insert(lines, Text.align_text("Server Status: Disconnected", width, "center", Text.highlights.warning))
            if #State.server_state.errors > 0 then
                -- Add section divider
                table.insert(lines, NuiLine())
                table.insert(lines, divider)
                table.insert(lines, NuiLine())
                table.insert(lines, NuiLine():append("Server Errors:", Text.highlights.error))
                local err = State.server_state.errors[#State.server_state.errors]
                local line = NuiLine()
                line:append("• ", Text.highlights.error)
                line:append(err.message, Text.highlights.error)
                if err.details then
                    line:append("\n  ")
                    line:append("Details: ", Text.highlights.muted)
                    line:append(vim.inspect(err.details), Text.highlights.muted)
                end
                table.insert(lines, line)
            end
        end
    end

    -- Add section divider
    table.insert(lines, NuiLine())
    table.insert(lines, divider)
    table.insert(lines, NuiLine())

    -- Add help text at bottom
    table.insert(lines, Text.align_text("Press:", width, "center", Text.highlights.muted))
    table.insert(lines,
        Text.align_text("(S)ervers   (T)ools   (R)esources   (C)onfig   (L)ogs   (?)Help", width, "center"))
    table.insert(lines, Text.align_text("q - Close window", width, "center", Text.highlights.muted))

    return lines
end

return MainView

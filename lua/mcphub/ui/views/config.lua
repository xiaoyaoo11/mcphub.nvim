---@brief [[
--- Config view for MCPHub UI
--- Shows MCP server configurations
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local validation = require("mcphub.validation")

---@class ConfigView
---@field super View
local ConfigView = setmetatable({}, {
    __index = View
})
ConfigView.__index = ConfigView

function ConfigView:new(ui)
    local self = View:new(ui, "config") -- Create base view with name
    return setmetatable(self, ConfigView)
end

function ConfigView:before_enter()
    View.before_enter(self)

    self.keymaps = {
        ["e"] = {
            action = function()
                if State.config and State.config.config then
                    self.ui:toggle()
                    vim.cmd("edit " .. State.config.config)
                else
                    vim.notify("No configuration file available", vim.log.levels.ERROR)
                end
            end,
            desc = "Edit config"
        }
    }
end

function ConfigView:get_initial_cursor_position()
    -- Position at start of server configurations
    local lines = self:render_header()
    if State.config and State.config.config then
        table.insert(lines, Text.pad_line(NuiLine():append("Config File: ", Text.highlights.muted)
            :append(State.config.config, Text.highlights.info)))
    end
    return #lines + 1
end

--- Render configuration for a single server
---@param server_name string
---@param config table
---@return NuiLine[]
function ConfigView:render_server_config(server_name, config)
    local lines = {}

    -- Server header with disabled status if any
    local header = NuiLine():append("• ", Text.highlights.muted):append(" " .. server_name .. " ",
        Text.highlights.header)
    if config.disabled then
        header:append(" ", Text.highlights.muted):append("(disabled)", Text.highlights.warning)
    end
    table.insert(lines, Text.pad_line(header))

    -- Show command
    if config.command then
        local cmd = config.command .. (#(config.args or {}) > 0 and " " .. table.concat(config.args, " ") or "")
        local cmd_line = NuiLine():append("  └─ Command: ", Text.highlights.muted):append(cmd, Text.highlights.info)
        table.insert(lines, Text.pad_line(cmd_line))
    end

    -- Show environment variables if any
    if config.env and not vim.tbl_isempty(config.env) then
        local env_header = NuiLine():append("  └─ Environment:", Text.highlights.muted)
        table.insert(lines, Text.pad_line(env_header))

        for name, _ in pairs(config.env) do
            local env_line = NuiLine():append("     • ", Text.highlights.muted):append(name, Text.highlights.info)
                :append(" = ", Text.highlights.muted):append("[hidden]", Text.highlights.warning)
            table.insert(lines, Text.pad_line(env_line))
        end
    end

    return lines
end

function ConfigView:render()
    -- Get base header
    local lines = self:render_header(false)
    local width = self:get_width()

    -- Show config file path
    if State.config and State.config.config then
        local file_line = NuiLine():append("Config File: ", Text.highlights.muted):append(State.config.config,
            Text.highlights.info)
        table.insert(lines, Text.pad_line(file_line))
    else
        table.insert(lines, Text.pad_line(NuiLine():append("Config File: ", Text.highlights.muted)
            :append("Not configured", Text.highlights.warning)))
    end

    -- Add separator
    table.insert(lines, self:divider())
    table.insert(lines, Text.empty_line())

    local file_validation = validation.validate_config_file(State.config.config)
    if file_validation.ok then
        if file_validation.json.mcpServers then
            local has_servers = false
            for name, cfg in pairs(file_validation.json.mcpServers) do
                has_servers = true
                vim.list_extend(lines, self:render_server_config(name, cfg))
                table.insert(lines, Text.empty_line())
            end

            if not has_servers then
                table.insert(lines, Text.align_text("No servers configured", width, "center", Text.highlights.warning))
            end
        end
    else
        table.insert(lines, Text.pad_line(NuiLine():append(file_validation.error.message, Text.highlights.error)))
        table.insert(lines, Text.empty_line())
    end

    return lines
end

return ConfigView

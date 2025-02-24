local MCPHub = require("mcphub.hub")
local log = require("mcphub.utils.log")
local Job = require("plenary.job")
local version = require("mcphub.version")
local State = require("mcphub.state")

local M = {}

--- @brief [[
--- Main module for MCPHub plugin
--- Provides setup and instance management functions
---
--- Usage:
--- ```lua
--- require('mcphub').setup({
---   port = 54321,
---   config = "~/.config/mcp/servers.json",
---   log = {
---     level = vim.log.levels.INFO,
---     to_file = true,
---     file_path = "~/.local/state/nvim/mcphub.log"
---   }
--- })
--- ```
--- @brief ]]

--- Setup function to configure the plugin
--- @param opts? { port?: number, config?: string, log?: table, on_ready?: fun(hub: MCPHub), on_error?: fun(err: string) }
--[[
Setup options:
- port: Port for MCP Hub server (default: auto-select)
- config: Path to server config file (default: ~/.config/mcp/servers.json)
- log: Logging configuration
  - level: Minimum log level (default: ERROR)
  - to_file: Whether to log to file (default: false)
  - file_path: Path to log file (default: nil)
  - prefix: Prefix for log messages (default: MCPHub)
- on_ready: Callback when server is ready(hub: MCPHub)
- on_error: Callback for setup errors(err: string)
--]]
function M.setup(opts)
    -- Return if already setup or in progress
    if State.setup_state ~= "not_started" then
        return State.hub_instance
    end

    State:update({
        setup_state = "in_progress"
    }, "setup")

    local config = vim.tbl_deep_extend("force", {
        port = nil,
        config = nil,
        log = {
            level = vim.log.levels.ERROR,
            to_file = false,
            file_path = nil,
            prefix = "MCPHub"
        },
        on_ready = function()
        end,
        on_error = function()
        end
    }, opts or {})

    log.setup(config.log or {})

    -- Create UI instance
    State.ui_instance = require("mcphub.ui"):new()

    -- Create command early
    vim.api.nvim_create_user_command("MCPHub", function()
        if State.ui_instance then
            State.ui_instance:toggle()
        else
            log.error("UI not initialized")
        end
    end, {
        desc = "Toggle MCP Hub window"
    })

    -- Setup cleanup
    local group = vim.api.nvim_create_augroup("mcphub_cleanup", {
        clear = true
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            if State.hub_instance then
                State.hub_instance:stop()
            end
            -- UI cleanup is handled by its own autocmd
        end
    })

    -- Start version check
    Job:new({
        command = "mcp-hub",
        args = {"--version"},
        on_exit = vim.schedule_wrap(function(j, code)
            if code ~= 0 then
                State:add_error({
                    type = "setup",
                    message = string.format("mcp-hub not found. Run 'npm install -g mcp-hub@%s'",
                        version.REQUIRED_NODE_VERSION.string)
                })
                State:update({
                    setup_state = "failed"
                }, "setup")
                config.on_error(State.setup_errors[#State.setup_errors].message)
                return
            end

            local ok, err = M.validate_version(j:result()[1])
            if not ok then
                State:add_error({
                    type = "setup",
                    message = err
                })
                State:update({
                    setup_state = "failed"
                }, "setup")
                config.on_error(State.setup_errors[#State.setup_errors].message)
                return
            end

            -- Create hub instance
            local hub = MCPHub:new(config)
            if not hub then
                State:add_error({
                    type = "setup",
                    message = "Failed to create MCPHub instance"
                })
                State:update({
                    setup_state = "failed"
                }, "setup")
                config.on_error(State.setup_errors[#State.setup_errors].message)
                return
            end

            -- Store hub instance with direct assignment to preserve metatable
            State.setup_state = "completed"
            State.hub_instance = hub
            State:notify_subscribers({
                setup_state = true,
                hub_instance = true
            }, "setup")

            -- Start hub
            hub:start({
                on_ready = config.on_ready,
                on_error = config.on_error
            })
        end)
    }):start()

    return State.hub_instance
end

--- Helper to parse and validate version
--- @param ver_str string Version string to validate
--- @return boolean is_valid Version is valid and compatible
--- @return string|nil error_message Error message if invalid
function M.validate_version(ver_str)
    local major, minor, patch = ver_str:match("(%d+)%.(%d+)%.(%d+)")
    if not major then
        return false, "Invalid version format"
    end

    local current = {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch)
    }

    local required = version.REQUIRED_NODE_VERSION
    if current.major ~= required.major or current.minor < required.minor then
        return false,
            string.format("Incompatible mcp-hub version. Found %s, required %s\nRun 'npm install -g mcp-hub@%s'",
                ver_str, required.string, required.string)
    end

    return true, nil
end

function M.get_hub_instance()
    if State.setup_state ~= "completed" then
        return nil
    end
    return State.hub_instance
end

function M.get_state()
    return State
end

return M

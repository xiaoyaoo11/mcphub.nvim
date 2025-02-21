local MCPHub = require("mcphub.hub")
local log = require("mcphub.utils.log")
local Job = require("plenary.job")
local version = require("mcphub.version")

--- @enum SetupState
local SetupState = {
    NOT_STARTED = "not_started",
    IN_PROGRESS = "in_progress",
    COMPLETED = "completed",
    FAILED = "failed"
}

--- @class MCPHubState
local state = {
    setup_state = SetupState.NOT_STARTED,
    setup_error = nil,
    hub_instance = nil
}

-- Helper to parse and validate version
local function validate_version(ver_str)
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

local M = {}

--- Setup function to configure the plugin
--- @param opts? { port?: number, config?: string, log?: table, on_ready?: fun(hub: MCPHub), on_error?: fun(err: string) }
function M.setup(opts)
    -- Already set up or in progress
    if state.setup_state ~= SetupState.NOT_STARTED then
        return state.hub_instance
    end

    state.setup_state = SetupState.IN_PROGRESS
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

    -- Create command early
    vim.api.nvim_create_user_command("MCPHub", function()
        if state.setup_error then
            log.error(state.setup_error)
            return
        end
        if state.hub_instance then
            state.hub_instance:display()
        else
            log.info("MCPHub is initializing...")
        end
    end, {
        desc = "Show MCP Hub status"
    })

    -- Setup cleanup early
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("mcphub_cleanup", {
            clear = true
        }),
        callback = function()
            if state.hub_instance then
                state.hub_instance:stop()
            end
        end
    })

    -- Start version check
    Job:new({
        command = "mcp-hub",
        args = {"--version"},
        on_exit = vim.schedule_wrap(function(j, code)
            if code ~= 0 then
                state.setup_error = string.format("mcp-hub not found. Run 'npm install -g mcp-hub@%s'",
                    version.REQUIRED_NODE_VERSION.string)
                state.setup_state = SetupState.FAILED
                config.on_error(state.setup_error)
                return
            end

            local ok, err = validate_version(j:result()[1])
            if not ok then
                state.setup_error = err
                state.setup_state = SetupState.FAILED
                config.on_error(err)
                return
            end

            -- Create instance
            state.hub_instance = MCPHub:new(config)
            if not state.hub_instance then
                state.setup_error = "Failed to create MCPHub instance"
                state.setup_state = SetupState.FAILED
                config.on_error(state.setup_error)
                return
            end

            -- Setup successful
            state.setup_state = SetupState.COMPLETED

            -- Start hub immediately
            state.hub_instance:start({
                on_ready = config.on_ready,
                on_error = config.on_error
            })
        end)
    }):start()

    return state.hub_instance
end

--- Get the MCPHub instance for direct access if needed
--- @return MCPHub | nil Instance or nil if not initialized
function M.get_hub_instance()
    if state.setup_state ~= SetupState.COMPLETED then
        log.error("MCPHub not initialized or setup failed")
        return nil
    end
    return state.hub_instance
end

return M

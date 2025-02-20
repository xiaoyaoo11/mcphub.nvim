local MCPHub = require("mcphub.hub")
local log = require("mcphub.utils.log")

--- @type MCPHub | nil
local hub_instance = nil

local M = {}

--- Setup function to configure the plugin
--- @param opts? { port?: number, config?: string, log?: table } Configuration options
function M.setup(opts)
    opts = opts or {}

    -- Setup logging first
    log.setup(opts.log or {})

    -- Return existing instance if already initialized
    if hub_instance then
        return hub_instance
    end

    -- Create new instance and store
    hub_instance = MCPHub:new(opts)
    if not hub_instance then
        return nil
    end

    -- Create the main command
    vim.api.nvim_create_user_command("MCPHub", function()
        hub_instance:display_status()
    end, {
        desc = "Show MCP Hub status"
    })

    -- Set up clean exit handler with unique namespace
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("mcphub_cleanup", {
            clear = true
        }),
        callback = function()
            if hub_instance then
                hub_instance:stop()
            end
        end
    })

    return hub_instance
end

--- Start the MCP Hub server
--- @param opts? { on_ready?: function, on_error?: function } Optional callbacks
function M.start_hub(opts)
    if not hub_instance then
        log.error("MCPHub not initialized. Call setup() first")
        return
    end
    hub_instance:start(opts)
end

--- Stop the MCP Hub connection
function M.stop_hub()
    if not hub_instance then
        log.error("MCPHub not initialized. Call setup() first")
        return
    end
    hub_instance:stop()
end

--- Get the MCPHub instance for direct access if needed
--- @return MCPHub | nil Instance or nil if not initialized
function M.get_hub_instance()
    return hub_instance
end

return M

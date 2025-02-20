local MCPHub = require("mcphub.hub")

--- @type MCPHub | nil
local hub_instance = nil

local M = {}

--- Setup function to configure the plugin
--- @param opts? { port?: number, config?: string } Configuration options
function M.setup(opts)
  -- Return existing instance if already initialized
  if hub_instance then
    return hub_instance
  end

  -- Create new instance and store
  hub_instance = MCPHub:new(opts or {})
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
    vim.notify("MCPHub not initialized. Call setup() first", vim.log.levels.ERROR)
    return
  end
  hub_instance:start(opts)
end

--- Stop the MCP Hub connection
function M.stop_hub()
  if not hub_instance then
    vim.notify("MCPHub not initialized. Call setup() first", vim.log.levels.ERROR)
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

local log = require("mcphub.utils.log")

local M = {}
function M.validate_opts(opts)
  -- Validate required options
  if not opts.port then
    log.error("Port is required")
    return false
  end

  if not opts.config then
    log.error("Config file path is required")
    return false
  else
    -- try to read and check if in correct syntax
    local file = io.open(opts.config, "r")
    if not file then
      log.error(string.format("Config file not found: %s", opts.config))
      return false
    end
    local content = file:read("*a")
    file:close()
    local success, json = pcall(vim.json.decode, content)
    if not success then
      log.error(string.format("Invalid JSON in config file: %s", opts.config))
      return false
    else
      if not json.mcpServers or (type(json.mcpServers) ~= "table") then
        log.error(string.format("Config file must contain 'mcpServers' array: %s", opts.config))
        return false
      end
    end
  end
  return true
end

return M

local M = {}

--- @class LogConfig
--- @field log_level number Default log level
--- @field to_file boolean Whether to log to file
--- @field file_path? string Path to log file
--- @field prefix string Prefix for log messages
local config = {
    log_level = vim.log.levels.WARN,
    to_file = false,
    file_path = nil,
    prefix = "MCPHub"
}

--- Setup logger configuration
--- @param opts LogConfig
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})

    -- Create log directory if logging to file
    if config.to_file and config.file_path then
        local path = vim.fn.fnamemodify(config.file_path, ":h")
        vim.fn.mkdir(path, "p")
    end
end

--- Internal logging function
--- @param msg string
--- @param level number
local function log_internal(msg, level)
    if level < config.log_level then
        return
    end

    local formatted = string.format("[%s] %s", config.prefix, msg)

    -- Log to file if configured
    if config.to_file and config.file_path then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local level_str = ({
            [vim.log.levels.DEBUG] = "DEBUG",
            [vim.log.levels.INFO] = "INFO",
            [vim.log.levels.WARN] = "WARN",
            [vim.log.levels.ERROR] = "ERROR"
        })[level] or "UNKNOWN"

        local log_line = string.format("%s [%s] %s\n", timestamp, level_str, formatted)
        local f = io.open(config.file_path, "a")
        if f then
            f:write(log_line)
            f:close()
        end
    end

    -- Always notify for errors
    if level >= vim.log.levels.ERROR then
        vim.notify(formatted, level)
        return
    end

    -- For other levels, only notify if level is within configured range
    if level >= config.log_level then
        vim.notify(formatted, level)
    end
end

--- Log a debug message
--- @param msg string
function M.debug(msg)
    log_internal(msg, vim.log.levels.DEBUG)
end

--- Log an info message
--- @param msg string
function M.info(msg)
    log_internal(msg, vim.log.levels.INFO)
end

--- Log a warning message
--- @param msg string
function M.warn(msg)
    log_internal(msg, vim.log.levels.WARN)
end

--- Log an error message
--- @param msg string
function M.error(msg)
    log_internal(msg, vim.log.levels.ERROR)
end

return M

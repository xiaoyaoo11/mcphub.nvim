local log = require("mcphub.utils.log")

local M = {}

--- Format timestamp relative to now
---@param timestamp number Unix timestamp
---@return string
function M.format_relative_time(timestamp)
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

return M

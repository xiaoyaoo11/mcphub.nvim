local log = require("mcphub.utils.log")

local M = {}

--- Format timestamp relative to now
---@param timestamp number Unix timestamp
---@return string
function M.format_relative_time(timestamp)
    local now = vim.loop.now()
    local diff = math.floor(now - timestamp)

    if diff < 1000 then -- Less than a second
        return "just now"
    elseif diff < 60000 then -- Less than a minute
        local seconds = math.floor(diff / 1000)
        return string.format("%ds", seconds)
    elseif diff < 3600000 then -- Less than an hour
        local minutes = math.floor(diff / 60000)
        local seconds = math.floor((diff % 60000) / 1000)
        return string.format("%dm %ds", minutes, seconds)
    elseif diff < 86400000 then -- Less than a day
        local hours = math.floor(diff / 3600000)
        local minutes = math.floor((diff % 3600000) / 60000)
        return string.format("%dh %dm", hours, minutes)
    else -- Days
        local days = math.floor(diff / 86400000)
        local hours = math.floor((diff % 86400000) / 3600000)
        return string.format("%dd %dh", days, hours)
    end
end

return M

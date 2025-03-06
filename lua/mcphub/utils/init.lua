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

--- Format duration in seconds to human readable string
---@param seconds number Duration in seconds
---@return string Formatted duration
function M.format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Calculate the approximate number of tokens in a text string
--- This is a simple approximation using word count, which works reasonably well for most cases
---@param text string The text to count tokens from
---@return number approx_tokens The approximate number of tokens
function M.calculate_tokens(text)
    if not text or text == "" then
        return 0
    end

    -- Simple tokenization approximation (4 chars ≈ 1 token)
    local char_count = #text
    local approx_tokens = math.ceil(char_count / 4)

    -- Alternative method using word count
    -- local words = {}
    -- for word in text:gmatch("%S+") do
    --     table.insert(words, word)
    -- end
    -- local word_count = #words
    -- local approx_tokens = math.ceil(word_count * 1.3) -- Words + punctuation overhead

    return approx_tokens
end

--- Format token count for display
---@param count number The token count
---@return string formatted The formatted token count
function M.format_token_count(count)
    if count < 1000 then
        return tostring(count)
    elseif count < 1000000 then
        return string.format("%.1fk", count / 1000)
    else
        return string.format("%.1fM", count / 1000000)
    end
end

return M

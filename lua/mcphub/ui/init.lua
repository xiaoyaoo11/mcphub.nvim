local M = {}

function M:new()
    local instance = {
        data = nil
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function M:show(data)
    -- Store server data
    self.data = data

    -- Show the data using vim.notify
    vim.notify(vim.inspect(data), vim.log.levels.INFO, {
        title = "MCP Hub Servers",
        timeout = 10000 -- 10 seconds
    })
end

return M

---@brief [[
--- Global state management for MCPHub
--- Handles setup, server, and UI state
---@brief ]]
---@class MCPState
local State = {
    -- Setup state
    setup_state = "not_started",
    setup_errors = {}, -- Array of setup related errors

    -- Core instances
    hub_instance = nil,
    ui_instance = nil,

    -- Server state
    server_state = {
        status = "disconnected", -- disconnected/connecting/connected
        pid = nil, -- Server process ID when running
        started_at = nil, -- When server was started
        errors = {} -- Server-related errors
    },

    -- Process streams
    output = {
        stdout = {}, -- Raw server stdout messages
        stderr = {} -- Raw server stderr messages
    },

    -- Logging messages
    logs = {
        debug = {},
        info = {},
        warn = {},
        error = {}
    },

    -- State management
    last_update = 0,
    subscribers = {
        ui = {}, -- UI-related subscribers
        server = {}, -- Server state subscribers
        all = {} -- All state changes subscribers
    }
}

function State:update(partial_state, update_type)
    update_type = update_type or "all"
    local changes = {}

    -- Track changes
    for k, v in pairs(partial_state) do
        if type(v) == "table" then
            if not vim.deep_equal(self[k], v) then
                changes[k] = true
                self[k] = vim.tbl_deep_extend("force", self[k] or {}, v)
            end
        else
            if self[k] ~= v then
                changes[k] = true
                self[k] = v
            end
        end
    end

    -- Notify if changed
    if next(changes) then
        self.last_update = vim.loop.now()
        self:notify_subscribers(changes, update_type)
    end
end

function State:add_error(error_obj)
    local error = {
        time = vim.loop.now(),
        message = error_obj.message,
        type = error_obj.type, -- 'setup', 'server', 'console'
        details = error_obj.details
    }

    if error_obj.type == "setup" then
        table.insert(self.setup_errors, error)
    elseif error_obj.type == "server" then
        table.insert(self.server_state.errors, error)
    end

    self:notify_subscribers({
        errors = true
    }, error_obj.type)
end

-- For raw server output (stdout/stderr)
function State:add_output(stream_type, data)
    if not self.output[stream_type] then
        return
    end
    table.insert(self.output[stream_type], {
        time = vim.loop.now(),
        data = data
    })
    -- Keep reasonable history
    if #self.output[stream_type] > 1000 then
        table.remove(self.output[stream_type], 1)
    end
    self:notify_subscribers({
        output = true
    }, "server")
end

-- For logging messages from log.lua
function State:add_log(level, msg)
    if not self.logs[level] then
        return
    end
    local entry = {
        time = vim.loop.now(),
        message = msg
    }
    table.insert(self.logs[level], entry)
    -- Keep reasonable history per level
    if #self.logs[level] > 1000 then
        table.remove(self.logs[level], 1)
    end
    self:notify_subscribers({
        logs = true
    }, "ui")
end

function State:subscribe(callback, types)
    types = types or {"all"}
    for _, type in ipairs(types) do
        if self.subscribers[type] then
            table.insert(self.subscribers[type], callback)
        end
    end
end

function State:notify_subscribers(changes, update_type)
    -- Notify type-specific subscribers
    if update_type ~= "all" and self.subscribers[update_type] then
        for _, callback in ipairs(self.subscribers[update_type]) do
            callback(self, changes)
        end
    end
    -- Always notify 'all' subscribers
    for _, callback in ipairs(self.subscribers.all) do
        callback(self, changes)
    end
end

return State

---@brief [[
--- Global state management for MCPHub
--- Handles setup, server, and UI state
---@brief ]]
---@class MCPState
local log = require("mcphub.utils.log")

local State = {
    -- Setup state
    setup_state = "not_started",

    -- Core instances
    hub_instance = nil,
    ui_instance = nil,

    -- Server state
    server_state = {
        status = "disconnected", -- disconnected/connecting/connected
        pid = nil, -- Server process ID when running
        started_at = nil, -- When server was started
        servers = {}
    },

    -- Error management
    errors = {
        setup = {}, -- Setup-time errors
        server = {}, -- Server-related errors
        runtime = {}, -- Runtime errors
        _by_id = {} -- Quick lookup by error ID
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

--- Add an error to state and optionally log it
---@param err MCPError The error to add
---@param log_level? string Optional explicit log level (debug/info/warn/error)
---@return string error_id The unique ID of the added error
function State:add_error(err, log_level)
    -- Generate unique error ID
    err.id = vim.fn.sha256(vim.fn.json_encode({
        type = err.type,
        code = err.code,
        message = err.message,
        timestamp = err.timestamp
    }))

    -- Add to appropriate category
    table.insert(self.errors[err.type:lower()], err)
    self.errors._by_id[err.id] = err

    -- Notify subscribers
    self:notify_subscribers({
        errors = true
    }, err.type:lower())

    -- Log with explicit level or infer from error type
    if log_level then
        log[log_level:lower()](tostring(err))
    else
        -- Default logging behavior based on error type
        local level = err.type == "SETUP" and "error" or err.type == "SERVER" and "warn" or "info"
        log[level](tostring(err))
    end

    return err.id
end

--- Clear errors of a specific type or all errors
---@param type? string Optional error type to clear (setup/server/runtime)
function State:clear_errors(type)
    if type then
        self.errors[type:lower()] = {}
    else
        for k, _ in pairs(self.errors) do
            if k ~= "_by_id" then
                self.errors[k] = {}
            end
        end
        self.errors._by_id = {}
    end
    self:notify_subscribers({
        errors = true
    }, "all")
end

--- Get error by ID
---@param id string Error ID
---@return MCPError|nil
function State:get_error(id)
    return self.errors._by_id[id]
end

--- Get all errors of a specific type
---@param type? string Optional error type (setup/server/runtime)
---@return MCPError[]
function State:get_errors(type)
    if type then
        return vim.deepcopy(self.errors[type:lower()] or {})
    end
    local all_errors = {}
    for k, errors in pairs(self.errors) do
        if k ~= "_by_id" then
            vim.list_extend(all_errors, errors)
        end
    end
    return all_errors
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

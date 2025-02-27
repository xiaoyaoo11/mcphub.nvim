---@brief [[
--- Global state management for MCPHub
--- Handles setup, server, and UI state
---@brief ]]
---@class MCPState
local log = require("mcphub.utils.log")

local State = {
    -- Setup state
    setup_state = "not_started",

    -- config
    config = {},

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

    -- Server output
    server_output = {
        entries = {} -- Chronological server output entries
    },

    -- State management
    last_update = 0,
    subscribers = {
        ui = {}, -- UI-related subscribers
        server = {}, -- Server state subscribers
        all = {} -- All state changes subscribers
    }
}

function State:reset()
    State.server_state = {
        status = "disconnected",
        pid = nil,
        started_at = nil,
        servers = {}
    }
    State.errors = {
        setup = {},
        server = {},
        runtime = {},
        _by_id = {}
    }
    State.server_output = {
        entries = {}
    }
    State.last_update = 0
end

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
    -- Add to appropriate category
    table.insert(self.errors[err.type:lower()], err)

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

-- For server output (stdout/stderr)
function State:add_server_output(entry)
    if not entry or not entry.type or not entry.message then
        return
    end

    -- Ensure entry has timestamp
    entry.timestamp = entry.timestamp or vim.loop.now()

    table.insert(self.server_output.entries, {
        type = entry.type, -- info/warn/error/debug
        message = entry.message, -- The actual message
        timestamp = entry.timestamp,
        data = entry.data -- Optional extra data
    })

    -- Keep reasonable history
    if #self.server_output.entries > 1000 then
        table.remove(self.server_output.entries, 1)
    end

    self:notify_subscribers({
        server_output = true
    }, "server")
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

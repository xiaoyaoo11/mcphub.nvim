---@brief [[
--- UI Core for MCPHub
--- Handles window/buffer management and view system
---@brief ]]
---@class MCPHubUI
local Text = require("mcphub.utils.text")
local State = require("mcphub.state")
local hl = require("mcphub.utils.highlights")

local UI = {}
UI.__index = UI

-- Constants for window sizing and layout
local WINDOW_CONSTANTS = {
    WIDTH_RATIO = 0.8,
    HEIGHT_RATIO = 0.8,
    MIN_WIDTH = 40
}

--- Create a new UI instance
---@return MCPHubUI
function UI:new()
    local instance = {
        window = nil, -- Window handle
        buffer = nil, -- Buffer handle
        current_view = nil, -- Current view name
        views = {} -- View instances
    }
    setmetatable(instance, self)

    -- Initialize views
    instance:init_views()

    -- Subscribe to state changes
    State:subscribe(function(_, changes)
        -- Only update UI if window is visible and relevant state changed
        if instance.window and vim.api.nvim_win_is_valid(instance.window) then
            -- Check if we need to update
            local should_update = false
            for k, _ in pairs(changes) do
                if k == "setup_state" or k == "server_state" or k == "logs" or k == "errors" then
                    should_update = true
                    break
                end
            end
            if should_update then
                -- Re-render current view
                instance:render()
            end
        end
    end, {"ui", "server", "setup"})

    -- Create cleanup autocommands
    local group = vim.api.nvim_create_augroup("mcphub_ui", {
        clear = true
    })

    -- Handle VimLeave
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            instance:cleanup()
        end
    })

    -- Handle window close
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            -- Check if the closed window is our window
            if instance.window and tonumber(args.match) == instance.window then
                instance:cleanup()
            end
        end
    })

    return instance
end

--- Initialize views
---@private
function UI:init_views()
    local MainView = require("mcphub.ui.views.main")

    -- Create view instances
    self.views = {
        main = MainView:new(self),
        servers = require("mcphub.ui.views.servers"):new(self),
        logs = require("mcphub.ui.views.logs"):new(self),
        help = require("mcphub.ui.views.help"):new(self),
        config = require("mcphub.ui.views.config"):new(self)
    }

    -- Set initial view
    self.current_view = "main"
end

--- Set up view-specific keymaps
function UI:setup_keymaps()
    local function map(key, action, desc)
        vim.keymap.set('n', key, action, {
            buffer = self.buffer,
            desc = desc,
            nowait = true
        })
    end

    -- Global navigation
    map('H', function()
        self:switch_view('main')
    end, "Switch to Home view")

    map('S', function()
        self:switch_view('servers')
    end, "Switch to Servers view")

    map('C', function()
        self:switch_view('config')
    end, "Switch to Config view")

    map('L', function()
        self:switch_view('logs')
    end, "Switch to Logs view")

    map('?', function()
        self:switch_view('help')
    end, "Switch to Help view")

    -- Close window
    map('q', function()
        self:cleanup()
    end, "Close window")
end

--- Create a new buffer for the UI
---@private
function UI:create_buffer()
    -- Create new buffer
    self.buffer = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(self.buffer, "modifiable", false)
    vim.api.nvim_buf_set_option(self.buffer, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(self.buffer, "filetype", "mcphub")
    vim.api.nvim_buf_set_option(self.buffer, "wrap", true)

    -- Set buffer mappings
    self:setup_keymaps()

    return self.buffer
end

--- Create a new window for the UI
---@private
function UI:create_window()
    if not self.buffer or not vim.api.nvim_buf_is_valid(self.buffer) then
        self:create_buffer()
    end

    -- Calculate dimensions with padding
    local width = math.max(WINDOW_CONSTANTS.MIN_WIDTH, math.floor(vim.o.columns * WINDOW_CONSTANTS.WIDTH_RATIO))
    -- Account for horizontal padding
    width = width - (Text.HORIZONTAL_PADDING * 2)

    local height = math.floor(vim.o.lines * WINDOW_CONSTANTS.HEIGHT_RATIO)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create floating window
    self.window = vim.api.nvim_open_win(self.buffer, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded"
    })

    -- Set up and apply window highlights 
    hl.setup()
    vim.api.nvim_win_set_option(self.window, "winhl",
        "Normal:" .. hl.groups.window_normal .. ",FloatBorder:" .. hl.groups.window_border)

    return self.window
end

--- Clean up resources
---@private
function UI:cleanup()
    -- Leave current view if any
    if self.current_view and self.views[self.current_view] then
        self.views[self.current_view]:on_leave()
    end

    -- Clean up buffer if it exists
    if self.buffer and vim.api.nvim_buf_is_valid(self.buffer) then
        vim.api.nvim_buf_delete(self.buffer, {
            force = true
        })
        self.buffer = nil
    end

    -- Close window if it exists
    if self.window and vim.api.nvim_win_is_valid(self.window) then
        vim.api.nvim_win_close(self.window, true)
        self.window = nil
    end
end

--- Toggle UI visibility
function UI:toggle()
    if self.window and vim.api.nvim_win_is_valid(self.window) then
        self:cleanup()
    else
        self:show()
    end
end

--- Switch to a different view
---@param view_name string Name of view to switch to
function UI:switch_view(view_name)
    -- Leave current view if any
    if self.current_view and self.views[self.current_view] then
        self.views[self.current_view]:on_leave()
    end

    -- Switch view
    self.current_view = view_name

    -- Enter new view
    if self.views[view_name] then
        self.views[view_name]:on_enter()
        -- Draw the view
        self.views[view_name]:draw()
    end
end

--- Show the UI window
function UI:show()
    -- Create/show window if needed
    if not self.window or not vim.api.nvim_win_is_valid(self.window) then
        self:create_window()
    end

    -- Focus window
    vim.api.nvim_set_current_win(self.window)

    -- Draw current view
    self:render()
end

--- Render current view
---@private
function UI:render()
    if self.current_view and self.views[self.current_view] then
        self.views[self.current_view]:draw()
    end
end

return UI

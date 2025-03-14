---@brief [[
--- Marketplace view for MCPHub UI
--- Browse, search and install MCP servers
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class MarketplaceView
---@field super View
---@field active_mode "browse"|"details" Current view mode
---@field selected_server table|nil Currently selected server
-- Helper functions
local function check_install_helper(name)
    -- Try to load the module and handle errors quietly
    local ok = pcall(require, name)
    return ok
end

local MarketplaceView = setmetatable({}, {
    __index = View,
})
MarketplaceView.__index = MarketplaceView

-- Static helper methods
function MarketplaceView.has_codecompanion()
    return check_install_helper("codecompanion")
end

function MarketplaceView:install_with_codecompanion(server)
    if not server or not server.mcpId then
        vim.notify("Invalid server data", vim.log.levels.ERROR)
        return
    end

    local codecompanion = require("codecompanion")
    local details = State.marketplace_state.server_details[server.mcpId]

    if not details or not details.data then
        vim.notify("Server details not available", vim.log.levels.ERROR)
        return
    end

    -- Get current config content and path
    local config_file = State.config.config
    local config_result = require("mcphub.validation").validate_config_file(config_file)
    local config_content = config_result.content or "{}"

    -- Get OS info
    local os_name = vim.loop.os_uname().sysname
    local is_windows = os_name == "Windows_NT"

    -- Build installation prompt
    local prompt = string.format(
        [[
I need to set up an MCP server. Please help me install it with these requirements:

Environment Details:
- OS: %s
- Config Path: %s (make sure we have write access)

Server Details:
- GitHub URL: %s
- MCP ID: %s

Tasks:
1. Read and analyze the current config:
%s

2. Install the server using %s commands
   Follow the README instructions below

3. Update the config file at %s
   Add the new server configuration

4. Verify the installation works

README Content:
-------------
%s
-------------]],
        os_name,
        config_file,
        server.githubUrl or "unknown URL",
        server.mcpId,
        config_content,
        is_windows and "Windows" or "Unix-like",
        config_file,
        details.data.readmeContent or "No README available"
    )

    -- Show starting notification
    vim.notify(string.format("Starting installation of %s with CodeCompanion...", server.name), vim.log.levels.INFO)

    -- Send prompt to CodeCompanion
    local chat = codecompanion.chat()
    chat:add_message({
        role = "user",
        content = prompt,
    }, {
        visible = false,
    })
    chat:add_buf_message({
        role = "user",
        content = "@files Please follow the installation instructions carefully.",
    })
end

function MarketplaceView:new(ui)
    local self = View:new(ui, "marketplace") -- Create base view with name
    self = setmetatable(self, MarketplaceView)

    -- Initialize state
    self.active_mode = "browse"
    self.selected_server = nil
    self.cursor_positions = {
        browse_mode = nil, -- Will store [line, col]
        details_mode = nil, -- Will store [line, col]
    }

    --  Setup initial keymaps (mode-specific keymaps set in setup_active_mode)
    self.keymaps = {}

    return self
end

function MarketplaceView:before_enter()
    View.before_enter(self)
    self:setup_active_mode()
end

function MarketplaceView:after_enter()
    View.after_enter(self)

    -- Restore appropriate cursor position for current mode
    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    if self.active_mode == "browse" and self.cursor_positions.browse_mode then
        local new_pos = {
            math.min(self.cursor_positions.browse_mode[1], line_count),
            self.cursor_positions.browse_mode[2],
        }
        vim.api.nvim_win_set_cursor(0, new_pos)
    elseif self.active_mode == "details" and self.cursor_positions.details_mode then
        local new_pos = {
            math.min(self.cursor_positions.details_mode[1], line_count),
            self.cursor_positions.details_mode[2],
        }
        vim.api.nvim_win_set_cursor(0, new_pos)
    end
end

function MarketplaceView:before_leave()
    -- Store current position based on mode
    if self.active_mode == "browse" then
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)
    else
        self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
    end
    View.before_leave(self)
end

function MarketplaceView:setup_active_mode()
    if self.active_mode == "browse" then
        self.keymaps = {
            ["/"] = {
                action = function()
                    -- TODO: Implement search focus
                    vim.notify("Search not yet implemented")
                end,
                desc = "Search",
            },
            ["<Tab>"] = {
                action = function()
                    local current = State.marketplace_state.filters.sort or "newest"
                    local sorts = { "newest", "stars", "name" }
                    local next_idx = 1
                    for i, sort in ipairs(sorts) do
                        if sort == current then
                            next_idx = (i % #sorts) + 1
                            break
                        end
                    end
                end,
                desc = "Change sort",
            },
            ["<CR>"] = {
                action = function()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local server = self:get_server_at_line(cursor[1])
                    if server then
                        -- Store browse mode position
                        self.cursor_positions.browse_mode = cursor
                        -- Switch to details mode
                        self.selected_server = server
                        self.active_mode = "details"
                        self:setup_active_mode()
                        -- Fetch details
                        if State.hub_instance then
                            State.hub_instance:get_marketplace_server_details(server.mcpId, {
                                callback = function(details, err)
                                    if err then
                                        vim.notify("Failed to fetch server details: " .. err, vim.log.levels.ERROR)
                                    end
                                    self:draw()
                                end,
                            })
                        end
                        self:draw()
                    end
                end,
                desc = "View details",
            },
        }
    else
        -- Details mode keymaps (simpler, focused on installation)
        self.keymaps = {
            ["<Esc>"] = {
                action = function()
                    -- Store details mode position
                    self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
                    -- Switch back to browse mode
                    self.active_mode = "browse"
                    self.selected_server = nil
                    self:setup_active_mode()
                    self:draw()
                    -- Restore browse mode position
                    if self.cursor_positions.browse_mode then
                        vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
                    end
                end,
                desc = "Back to list",
            },
            ["<CR>"] = {
                action = function()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local type, context = self:get_line_info(cursor[1])
                    if type == "install" then
                        -- Check for server existence
                        local current_servers = State.server_state.servers or {}
                        for _, server in ipairs(current_servers) do
                            if server.name == context.mcpId then
                                vim.notify("This MCP server is already installed", vim.log.levels.ERROR)
                                return
                            end
                        end

                        -- Check for CodeCompanion
                        if MarketplaceView.has_codecompanion() then
                            vim.ui.select({ "Yes", "No" }, {
                                prompt = "Install using CodeCompanion?",
                            }, function(choice)
                                if choice == "Yes" then
                                    -- Close UI first
                                    if self.ui then
                                        self.ui:cleanup()
                                    end
                                    -- Start installation
                                    self:install_with_codecompanion(self.selected_server)
                                end
                            end)
                        else
                            vim.notify(
                                "CodeCompanion not found. Please install CodeCompanion or Avante for automated installation.",
                                vim.log.levels.ERROR
                            )
                        end
                    end
                end,
                desc = "Install",
            },
        }
    end
    self:apply_keymaps()
end

-- Helper to find server at cursor line
function MarketplaceView:get_server_at_line(line)
    local type, context = self:get_line_info(line)
    if type == "server" and context.mcpId then
        -- Look up server in catalog by id
        for _, server in ipairs(State.marketplace_state.catalog.items) do
            if server.mcpId == context.mcpId then
                return server
            end
        end
    end
    return nil
end

function MarketplaceView:render_header_controls()
    local lines = {}
    local width = self:get_width() - (Text.HORIZONTAL_PADDING * 2)

    -- Create left and right sections
    local left_section = NuiLine()
        :append(Text.icons.sort .. " ", Text.highlights.title)
        :append("Sort: ", Text.highlights.muted)
        :append("Newest", Text.highlights.info)
        :append("  ", Text.highlights.muted)
        :append(Text.icons.tag .. " ", Text.highlights.title)
        :append("Category: ", Text.highlights.muted)
        :append("All", Text.highlights.info)

    local right_section =
        NuiLine():append(Text.icons.search .. " ", Text.highlights.title):append("/ to search", Text.highlights.muted)

    -- Calculate padding needed between sections
    local total_content_width = left_section:width() + right_section:width()
    local padding = width - total_content_width

    -- Combine sections with padding
    local controls_line = NuiLine():append(left_section):append(string.rep(" ", padding)):append(right_section)

    table.insert(lines, Text.pad_line(controls_line))
    table.insert(lines, self:divider())

    return lines
end

function MarketplaceView:fetch_catalog()
    local filters = State.marketplace_state.filters or {}
    if State.hub_instance then
        State.hub_instance:get_marketplace_catalog({
            sort = filters.sort,
            category = filters.category,
            search = filters.search,
            callback = function(_, err)
                if err then
                    vim.notify("Failed to fetch marketplace: " .. err, vim.log.levels.ERROR)
                end
                self:draw()
            end,
        })
    end
end

function MarketplaceView:render_server_card(server, index)
    local lines = {}
    local width = self:get_width() - (Text.HORIZONTAL_PADDING * 2)

    -- Create server name section (left part)
    local name_section = NuiLine()
        :append(Text.icons.triangleRight .. " ", Text.highlights.info)
        :append(server.name, Text.highlights.info)

    -- Create metadata section (right part)
    local meta_section = NuiLine()
        :append(Text.icons.favorite, Text.highlights.muted)
        :append("" .. (server.githubStars or "0"), Text.highlights.muted)
    -- :append(" | ", Text.highlights.muted)
    -- :append(Text.icons.octoface .. " ", Text.highlights.title)
    -- :append(server.author, Text.highlights.muted)
    -- :append(" | ", Text.highlights.muted)
    -- :append(Text.icons.tag .. " ", Text.highlights.title)
    -- :append(server.category, Text.highlights.muted)

    -- Calculate padding between name and metadata
    local padding = 2 -- width - (name_section:width() + meta_section:width())

    -- Combine name and metadata with padding
    local title_line = NuiLine():append(name_section):append(string.rep(" ", padding)):append(meta_section)

    -- Track line for server selection (storing only id)
    self:track_line(index, "server", {
        type = "server",
        mcpId = server.mcpId,
        hint = "Press <CR> for details",
    })
    table.insert(lines, Text.pad_line(title_line))

    -- Description (with spacing)
    if server.description then
        -- table.insert(lines, Text.pad_line(NuiLine())) -- Add blank line before description
        table.insert(lines, Text.pad_line(NuiLine():append(server.description, Text.highlights.muted)))
    end

    table.insert(lines, Text.pad_line(NuiLine()))
    return lines
end

function MarketplaceView:render_browse_mode(line_offset)
    local lines = {}

    -- Render controls
    vim.list_extend(lines, self:render_header_controls())

    -- Show appropriate state
    local state = State.marketplace_state
    if state.status == "loading" then
        table.insert(lines, Text.pad_line(NuiLine():append("Loading marketplace catalog...", Text.highlights.muted)))
    elseif state.status == "error" then
        table.insert(
            lines,
            Text.pad_line(
                NuiLine()
                    :append(Text.icons.error .. " ", Text.highlights.error)
                    :append("Failed to load marketplace", Text.highlights.error)
            )
        )
    else
        -- Show server catalog
        local items = state.catalog.items
        if #items == 0 then
            table.insert(
                lines,
                Text.pad_line(NuiLine():append("No servers found in marketplace", Text.highlights.muted))
            )
        else
            for i, server in ipairs(items) do
                -- Pass current line number considering line_offset
                vim.list_extend(lines, self:render_server_card(server, #lines + line_offset + 1))
            end
        end
    end

    return lines
end

function MarketplaceView:render_details_mode(line_offset)
    local lines = {}
    local server = self.selected_server
    if not server then
        return lines
    end

    -- Description
    if server.description then
        table.insert(lines, Text.multiline(server.description, Text.highlights.muted))
    end

    -- Server info section
    local info_lines = {
        {
            label = "URL   ",
            icon = Text.icons.event,
            value = server.githubUrl,
            is_url = true,
        },
        {
            label = "Author",
            icon = Text.icons.octoface,
            value = server.author or "Unknown",
        },
    }

    -- Add category and tags together
    if server.category then
        local category_value = server.category
        if type(server.tags) == "table" and #server.tags > 0 then
            category_value = category_value .. " [" .. table.concat(server.tags, ", ") .. "]"
        end
        table.insert(info_lines, {
            label = "Tags  ",
            icon = Text.icons.tag,
            value = server.category,
            suffix = type(server.tags) == "table"
                    and #server.tags > 0
                    and (" [" .. table.concat(server.tags, ", ") .. "]")
                or nil,
        })
    end

    -- Render info lines
    for _, info in ipairs(info_lines) do
        if info.value then
            local line = NuiLine()
                -- :append(info.icon .. "", Text.highlights.title)
                :append(
                    info.label .. " : ",
                    Text.highlights.muted
                )
                :append(info.value, info.is_url and Text.highlights.link or Text.highlights.info)

            if info.suffix then
                line:append(info.suffix, Text.highlights.muted)
            end

            table.insert(lines, Text.pad_line(line))
        end
    end
    table.insert(lines, Text.pad_line(NuiLine()))

    -- Install button (capability-style highlight)
    if server.mcpId then
        local install_line = NuiLine():append("[ Install ]", Text.highlights.active_item)
        table.insert(lines, Text.pad_line(install_line))

        -- Track install button
        self:track_line(#lines + line_offset, "install", {
            type = "install",
            mcpId = server.mcpId,
            server = server, -- Keep server info for installation
            hint = "Press <CR> to install",
        })

        table.insert(lines, Text.pad_line(NuiLine()))
        table.insert(lines, self:divider())
    end

    -- Readme section with safety checks
    local details = State.marketplace_state.server_details[server.mcpId]
    if details and details.data and type(details.data.readmeContent) == "string" then
        local readme = details.data.readmeContent
        if #readme > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("README", Text.highlights.title)))
            table.insert(lines, Text.pad_line(NuiLine()))
            for _, line in ipairs(vim.split(readme, "\n")) do
                if type(line) == "string" then
                    table.insert(lines, Text.pad_line(NuiLine():append(line, Text.highlights.muted)))
                end
            end
        end
    end

    return lines
end

function MarketplaceView:render()
    -- Get base header
    local lines = self:render_header(false)

    -- Add title/breadcrumb
    if self.active_mode == "browse" then
        table.insert(lines, Text.pad_line(NuiLine():append("Marketplace", Text.highlights.title)))
    elseif self.selected_server then
        local breadcrumb = NuiLine()
            :append("Marketplace > ", Text.highlights.muted)
            :append(self.selected_server.name, Text.highlights.title)
        if self.selected_server.githubStars and self.selected_server.githubStars > 0 then
            breadcrumb
                :append(" (" .. Text.icons.favorite, Text.highlights.muted)
                :append(tostring(self.selected_server.githubStars) .. ")", Text.highlights.muted)
        end
        table.insert(lines, Text.pad_line(breadcrumb))
    else
        -- Fallback if server not loaded yet
        local breadcrumb = NuiLine():append("Marketplace", Text.highlights.title)
        table.insert(lines, Text.pad_line(breadcrumb))
    end
    table.insert(lines, self:divider())

    -- Calculate line offset from header
    local line_offset = #lines

    -- Render current mode with line offset
    if self.active_mode == "browse" then
        vim.list_extend(lines, self:render_browse_mode(line_offset))
    else
        vim.list_extend(lines, self:render_details_mode(line_offset))
    end

    return lines
end

return MarketplaceView

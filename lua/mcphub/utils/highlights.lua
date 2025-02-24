--[[ MCPHub highlight utilities ]] local M = {}

-- Highlight group names
M.groups = {
    title = "MCPHubTitle",
    header = "MCPHubHeader",
    header_btn = "MCPHubHeaderBtn",
    header_btn_shortcut = "MCPHubHeaderBtnShortcut",
    header_shortcut = "MCPHubHeaderShortcut",
    error = "MCPHubError",
    warning = "MCPHubWarning",
    info = "MCPHubInfo",
    success = "MCPHubSuccess",
    muted = "MCPHubMuted",
    window_normal = "MCPHubNormal",
    window_border = "MCPHubBorder"
}

-- Setup highlight groups
function M.setup()
    local highlights = {
        -- Window elements
        [M.groups.window_normal] = {
            bg = "#1a1b26",
            fg = "#c0caf5"
        },
        [M.groups.window_border] = {
            bg = "NONE",
            fg = "#555555", -- Dark gray for border
            special = "#555555" -- Match border char color
        },

        -- Title and headers
        [M.groups.title] = {
            bg = "NONE",
            fg = "#c792ea", -- Purple for titles
            bold = true
        },
        [M.groups.header] = {
            bg = "#444444",
            fg = "#d4d4d4" -- Light gray for normal text
        },
        [M.groups.header_btn] = {
            fg = "#222222",
            bg = "#c792ea",
            bold = true
        },
        [M.groups.header_btn_shortcut] = {
            bg = "#c792ea",
            fg = "#111111",
            bold = true
        },
        [M.groups.header_shortcut] = {
            bg = "#444444",
            fg = "#ff966c", -- Orange for shortcuts
            bold = true
        },

        -- Status and messages
        [M.groups.error] = {
            bg = "NONE",
            fg = "#f44747" -- Red for errors
        },
        [M.groups.warning] = {
            bg = "NONE",
            fg = "#ff8800" -- Orange for warnings
        },
        [M.groups.info] = {
            bg = "NONE",
            fg = "#4fc1ff" -- Light blue for info
        },
        [M.groups.success] = {
            bg = "NONE",
            fg = "#89d185" -- Green for success
        },
        [M.groups.muted] = {
            bg = "NONE",
            fg = "#808080" -- Gray for muted text
        }
    }

    -- -- Clear any existing highlights
    -- for name, _ in pairs(highlights) do
    --     vim.api.nvim_set_hl(0, name, {})
    -- end
    -- Set new highlights
    for name, val in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, val)
    end
end

return M

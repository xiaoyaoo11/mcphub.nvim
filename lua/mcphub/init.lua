local MCPHub = require('mcphub.mcphub')

local M = {}

--- Setup function for configuring the plugin
--- @param opts table Configuration options
--- @field port number Port number for the MCP Hub server (default: 3000)
--- @field config string Path to the MCP servers configuration file
--- @field watch boolean Whether to watch the config file for changes (default: false)
--- @field commands table Optional table of user commands to create
--- @field keymaps table Optional table of keymaps to set up
function M.setup(opts)
    if not opts then
        error('mcphub.setup() requires a configuration table')
    end

    if not opts.port then
        error('mcphub.setup() requires a port number')
    end

    if not opts.config then
        error('mcphub.setup() requires a config file path')
    end

    M.instance = MCPHub:new(opts)
    M.instance:initialize()

    -- Set up single user command
    vim.api.nvim_create_user_command('MCPHub', function()
        M.instance:show()
    end, {
        desc = 'Show MCP Hub interface'
    })

    -- Set up optional keymaps
    if opts.keymaps then
        for lhs, rhs in pairs(opts.keymaps) do
            vim.keymap.set('n', lhs, rhs, {
                silent = true,
                noremap = true
            })
        end
    end
end

return M

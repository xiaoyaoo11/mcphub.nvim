# MCPHub.nvim

Neovim plugin for managing MCP (Model Context Protocol) servers through [mcp-hub](https://github.com/ravitemer/mcp-hub).

## Features

- Simple single-command interface (`:MCPHub`)
- Automatic server lifecycle management
- Clean client registration/cleanup
- Smart process handling

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",  -- Required for HTTP requests
    },
    build = function()
        -- Install mcp-hub globally
        vim.fn.system("npm install -g mcp-hub")
    end,
    config = function()
        require("mcphub").setup({
            port = 3000,  -- Port for MCP Hub server
            config = vim.fn.expand("~/.config/mcp-hub/config.json")  -- Config file path
        })
    end
}
```

## Usage

### For Chat Plugin Developers

```lua
local mcphub = require("mcphub")

-- Setup plugin
mcphub.setup({
    port = 3000,
    config = vim.fn.expand("~/.config/mcp-hub/config.json")
})

-- Start server/connect
mcphub.start_hub({
    on_ready = function(hub_instance)
        -- Ready to use MCP features
        local servers = hub_instance:get_servers()
    end,
    on_error = function(err)
        vim.notify("MCP Hub error: " .. err, vim.log.levels.ERROR)
    end
})

-- Get instance for API access
local hub = mcphub.get_hub_instance()

-- Use MCP tools
local result = hub:call_tool("server-name", "tool-name", {
    -- Tool arguments
})

-- Access resources
local resource = hub:access_resource("server-name", "resource://uri")

-- Shutdown (optional, handled automatically on `VIMLeavePre`)
-- mcphub.stop_hub()
```

## Architecture

### Server Lifecycle

![Server Lifecycle](public/diagrams/server-lifecycle.png)

The diagram above shows how multiple Neovim instances interact with a single MCP Hub server. The first instance starts the server, while others connect to the existing one. When the last client disconnects, the server automatically shuts down.

### Request Flow

![Request Flow](public/diagrams/request-flow.png)

Detailed sequence of how the plugin interacts with the MCP Hub server, from initial startup to status display, showing both the startup sequence and normal operation.

### Cleanup Process

![Cleanup Flow](public/diagrams/cleanup-flow.png)

The cleanup process ensures proper resource management and server shutdown. It handles both individual client disconnection and full server shutdown when appropriate.

### API Interaction

![API Flow](public/diagrams/api-interaction.png)

Shows how chat plugins can interact with MCP servers through our plugin's API, including error handling and status checking.

## Requirements

- Neovim >= 0.8.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Node.js >= 18.0.0 (for mcp-hub)
- [mcp-hub](https://github.com/ravitemer/mcp-hub)

## Troubleshooting

1. **Server Won't Start**

   - Check if port is available
   - Verify mcp-hub installation
   - Check config file path

2. **Connection Issues**

   - Ensure server is running
   - Check port configuration
   - Verify client registration

3. **Status Shows Not Ready**
   - Call mcphub.start_hub()
   - Check server health
   - Verify connection state

## License

MIT License - See LICENSE file for details

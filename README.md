# MCPHub.nvim

Neovim plugin for managing MCP (Model Context Protocol) servers through [mcp-hub](https://github.com/ravitemer/mcp-hub).

## Features

- Simple single-command interface (`:MCPHub`)
- Automatic server lifecycle management
- Async operations - no blocking
- Clean client registration/cleanup
- Smart process handling
- Configurable logging support

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
            config = vim.fn.expand("~/.config/mcp-hub/config.json"),  -- Config file path
            log = {  -- Optional logging configuration
                level = vim.log.levels.WARN,  -- Log level (ERROR, WARN, INFO, DEBUG)
                to_file = false,  -- Whether to log to file
                file_path = nil,  -- Log file path
                prefix = "MCPHub"  -- Log message prefix
            }
        })
    end
}
```

## Usage

### For Chat Plugin Developers

```lua
local mcphub = require("mcphub")

-- Setup plugin with logging
mcphub.setup({
    port = 3000,
    config = vim.fn.expand("~/.config/mcp-hub/config.json"),
})

-- Start server/connect
mcphub.start_hub({
    on_ready = function(hub_instance)
        -- Ready to use MCP features
        hub_instance:get_servers(function(servers)
            -- Use servers data
        end)
    end,
    on_error = function(err)
        -- Error will be automatically logged
    end
})

-- Get instance for API access (all methods are async)
local hub = mcphub.get_hub_instance()

-- Call a tool
hub:call_tool("server-name", "tool-name", {
    -- Tool arguments
}, function(result, error)
    if error then
        -- Error will be automatically logged at appropriate level
        return
    end
    -- Use tool result
end)

-- Access resources
hub:access_resource("server-name", "resource://uri", function(resource, error)
    if error then
        -- Error will be automatically logged
        return
    end
    -- Use resource data
end)

-- Get server status
hub:get_status(function(status)
    -- Use status information
end)

-- Get available servers
hub:get_servers(function(servers)
    -- Use servers list
end)

-- Get specific server info
hub:get_server_info("server-name", function(server)
    if server then
        -- Server found
    else
        -- Server not found
    end
end)

-- Shutdown (optional, handled automatically on `VimLeavePre`)
-- mcphub.stop_hub()
```

## API Reference

### REST API Endpoints

You can directly access the MCP Hub server's API at `http://localhost:<port>/api/`. Available endpoints:

- `GET /api/health` - Server health check
- `GET /api/servers` - List all connected servers
- `GET /api/servers/{name}` - Get specific server info
- `POST /api/servers/{name}/tools` - Call a tool
- `POST /api/servers/{name}/resources` - Access a resource

### MCP Server Schema

Each MCP Server information follows this schema:

```typescript
{
  name: string,
  status: "disconnected" | "connecting" | "connected",
  error: string | null,
  capabilities: {
    tools: Array<{
      name: string,
      description: string,
      parameters: object // Tool-specific parameters
    }>,
    resources: Array<{
      uri: string,
      type: string
    }>,
    resourceTemplates: Array<{
      uriTemplate: string,
      type: string
    }>
  },
  uptime: number,    // Server uptime in seconds
  lastStarted: string // ISO timestamp
}
```

### Tool Response Schema

```typescript
{
  result: any, // Tool-specific result data
  error?: string // Error message if failed
}
```

### Resource Response Schema

```typescript
{
  content: any,   // Resource content
  type: string,   // Resource type
  error?: string  // Error message if failed
}
```

For development and debugging, you can directly query these endpoints.

## Architecture

### Server Lifecycle

![Server Lifecycle](public/diagrams/server-lifecycle.png)

The diagram above shows how multiple Neovim instances interact with a single MCP Hub server. The first instance starts the server, while others connect to the existing one. When the last client disconnects, the server automatically shuts down.

### Request Flow

![Request Flow](public/diagrams/request-flow.png)

All operations are asynchronous, using callbacks to handle responses. This ensures Neovim stays responsive even during network operations. The diagram shows the request flow from initial startup to status display.

### Cleanup Process

![Cleanup Flow](public/diagrams/cleanup-flow.png)

The cleanup process ensures proper resource management and server shutdown. It handles both individual client disconnection and full server shutdown when appropriate.

### API Interaction

![API Flow](public/diagrams/api-interaction.png)

All API interactions are asynchronous and follow this pattern:

1. Check ready state
2. Make request
3. Handle response in callback
4. Error handling in callback

## Async API Reference

```lua
-- Server Management
hub:check_server(callback)           -- callback(is_running: boolean)
hub:get_status(callback)            -- callback(status: table)
hub:get_servers(callback)           -- callback(servers: table)
hub:get_server_info(name, callback) -- callback(server: table|nil)

-- Tool/Resource Access
hub:call_tool(server, tool, args, callback)      -- callback(result: table|nil, error?: string)
hub:access_resource(server, uri, callback)       -- callback(result: table|nil, error?: string)

-- Health/Status
hub:is_ready()        -- returns boolean (sync, safe to call)
hub:display_status()  -- shows UI with current status
```

## Logging Configuration

The plugin supports configurable logging with the following options:

```lua
{
    level = vim.log.levels.WARN,  -- Log level threshold
    to_file = false,             -- Enable file logging
    file_path = nil,             -- Path to log file
    prefix = "MCPHub"            -- Prefix for log messages
}
```

## Requirements

- Neovim >= 0.8.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Node.js >= 18.0.0 (for mcp-hub)
- [mcp-hub](https://github.com/ravitemer/mcp-hub)

## Error Handling

```lua
-- Example error handling pattern
hub:call_tool("server", "tool", args, function(result, error)
    if error then
        -- Errors are automatically logged at appropriate levels
        return
    end
    -- Use result
end)
```

## Troubleshooting

1. **Server Won't Start**

   - Check if port is available
   - Verify mcp-hub installation
   - Check config file path
   - Enable DEBUG log level for detailed output
   - Check log file if file logging enabled
   - Test API directly: `curl http://localhost:3000/api/health`

2. **Connection Issues**

   - Ensure server is running (quick health check timeout)
   - Check port configuration
   - Verify client registration
   - Monitor log output for connection attempts
   - Test API endpoints directly with curl

3. **Status Shows Not Ready**
   - Call mcphub.start_hub()
   - Check server health
   - Verify connection state
   - Check error callbacks
   - Review logs for startup sequence
   - Check API health endpoint

## License

MIT License - See LICENSE file for details

# MCPHub.nvim

[![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

> A powerful Neovim plugin for managing MCP (Model Context Protocol) servers through [mcp-hub](https://github.com/ravitemer/mcp-hub).

## ✨ Features

- Simple single-command interface (`:MCPHub`)
- Automatic server lifecycle management
- Both sync and async operations supported
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
    build = "npm install -g mcp-hub@latest", -- Install specific version
    config = function()
        require("mcphub").setup({
            port = 3000,  -- Port for MCP Hub server
            config = vim.fn.expand("~/.config/mcp-hub/config.json"),  -- Config file path
            log = {  -- Optional logging configuration
                level = vim.log.levels.WARN,  -- Log level (ERROR, WARN, INFO, DEBUG)
                to_file = false,  -- Whether to log to file
                file_path = nil,  -- Log file path
                prefix = "MCPHub"  -- Log message prefix
            },
            on_ready = function(hub)
                -- Called when hub is ready
            end,
            on_error = function(err)
                -- Called on errors
            end
        })
    end
}
```

## Usage

### For A Chat Plugin

```lua
local mcphub = require("mcphub")

-- Setup plugin with logging and callbacks
mcphub.setup({
    port = 3000,
    config = vim.fn.expand("~/.config/mcp-hub/config.json"),
    on_ready = function(hub)
        -- Ready to use MCP features
        -- Using async mode (non-blocking)
        hub:get_servers({
            callback = function(response, err)
                if err then return end
                local servers = response.servers -- Extract servers from response
                -- Use servers data
            end
        })

        -- Or using sync mode (blocking)
        local response, err = hub:get_servers()
        if not err then
            local servers = response.servers -- Extract servers from response
        end
    end,
    on_error = function(err)
        -- Error will be automatically logged
    end
})

-- Get instance for API access
local hub = mcphub.get_hub_instance()

-- All methods support both sync and async modes and return raw responses:

-- Async mode (non-blocking)
hub:call_tool("server-name", "tool-name", {
    -- Tool arguments
}, {
    callback = function(response, error)
        if error then
            -- Error will be automatically logged at appropriate level
            return
        end
        local result = response.result -- Extract result from response
        -- Use tool result
    end
})

-- Sync mode (blocking)
local response, error = hub:call_tool("server-name", "tool-name", {
    -- Tool arguments
})
if error then
    -- Handle error
    return
end
local result = response.result -- Extract result from response
-- Use result

-- Access resources (async)
hub:access_resource("server-name", "resource://uri", {
    callback = function(response, error)
        if error then
            -- Error will be automatically logged
            return
        end
        local content = response.content -- Extract content from response
        -- Use resource data
    end
})

-- Access resources (sync)
local response, error = hub:access_resource("server-name", "resource://uri")
if error then
    -- Handle error
    return
end
local content = response.content -- Extract content from response
-- Use resource data

-- Get server status (async)
hub:get_health({
    callback = function(response, err)
        if err then return end
        -- Use raw response information
    end
})

-- Get server status (sync)
local response, err = hub:get_health()
if not err then
    -- Use raw response
end

-- Get available servers (async)
hub:get_servers({
    callback = function(response, err)
        if err then return end
        local servers = response.servers -- Extract servers from response
        -- Use servers list
    end
})

-- Get available servers (sync)
local response, err = hub:get_servers()
if not err then
    local servers = response.servers -- Extract servers from response
end

-- Get specific server info (async)
hub:get_server_info("server-name", {
    callback = function(response, err)
        if err then return end
        if response.server then -- Extract server from response
            -- Server found
        else
            -- Server not found
        end
    end
})

-- Get specific server info (sync)
local response, err = hub:get_server_info("server-name")
if not err and response.server then -- Extract server from response
    -- Server found
else
    -- Server not found
end
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
      inputSchema: object // Tool-specific parameters
    }>,
    resources: Array<{
      uri: string,
      name: string,
      mimeTime: string
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
result : any,
error?: string
}
```

## API Reference

```lua
-- Server Management (all support both sync/async and return raw responses)
hub:check_server(opts?)           -- callback(is_running: boolean) or returns boolean
hub:get_health(opts?)            -- callback(response: table, error?: string) or returns table|nil, string|nil
hub:get_servers(opts?)           -- callback(response: table, error?: string) or returns table|nil, string|nil
hub:get_server_info(name, opts?) -- callback(response: table, error?: string) or returns table|nil, string|nil

-- Tool/Resource Access (all support both sync/async and return raw responses)
hub:call_tool(server, tool, args, opts?)      -- callback(response: table|nil, error?: string) or returns table|nil, string|nil
hub:access_resource(server, uri, opts?)       -- callback(response: table|nil, error?: string) or returns table|nil, string|nil

-- Health/Status
hub:is_ready()        -- returns boolean (sync, safe to call)
```

## Architecture

### Server Lifecycle

![Server Lifecycle](public/diagrams/server-lifecycle.png)

The diagram above shows how multiple Neovim instances interact with a single MCP Hub server. The first instance starts the server, while others connect to the existing one. When the last client disconnects, the server automatically shuts down.

### Request Flow

![Request Flow](public/diagrams/request-flow.png)

Operations can be either synchronous (blocking) or asynchronous (using callbacks). The diagram shows the request flow from initial startup to status display.

### Cleanup Process

![Cleanup Flow](public/diagrams/cleanup-flow.png)

The cleanup process ensures proper resource management and server shutdown. It handles both individual client disconnection and full server shutdown when appropriate.

### API Interaction

![API Flow](public/diagrams/api-interaction.png)

All API functions support both sync and async patterns:

1. Sync: Direct return values (raw responses)
2. Async: Handle response in callback
3. Error handling in both modes
4. State management carried through

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
-- Example error handling (async mode)
hub:call_tool("server", "tool", args, {
    callback = function(response, error)
        if error then
            -- Errors are automatically logged at appropriate levels
            return
        end
        local result = response.result -- Extract result from response
        -- Use result
    end
})

-- Example error handling (sync mode)
local response, error = hub:call_tool("server", "tool", args)
if error then
    -- Handle error
    return
end
local result = response.result -- Extract result from response
-- Use result
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
   - Check server health
   - Verify connection state
   - Check error callbacks
   - Review logs for startup sequence
   - Check API health endpoint

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](./CONTRIBUTING.md) for details on how to submit pull requests, report issues, and contribute to the project.

## 🔒 Security

Found a security issue? Please review our [Security Policy](./SECURITY.md) and follow the vulnerability reporting process.

## 📝 Changelog

See [CHANGELOG.md](./CHANGELOG.md) for a detailed list of changes between releases.

## 📜 Code of Conduct

This project follows a [Code of Conduct](./CODE_OF_CONDUCT.md) to ensure a welcoming and inclusive environment for all contributors.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE.md](./LICENSE.md) file for details.

## 🗺️ Roadmap

### Upcoming Features

1. **Enhanced UI Integration**

   - Lazy.nvim/Mason-style interface for MCP server management
   - Interactive server status dashboard
   - Tool and resource browser with filtering and search
   - Rich command palette integration
   - Floating windows for tool execution and resource viewing

2. **Prompt Engineering Utilities**

   - Smart server selection based on prompt content
   - Automatic tool/resource selection helpers
   - Prompt templates and generators
   - Context-aware prompt building
   - Response parsing and formatting utilities

3. **Server Management Improvements**

   - Server health monitoring dashboard
   - Performance metrics and analytics
   - Auto-recovery and failover strategies
   - Configuration management UI
   - Batch operations support

4. **Developer Tools**

   - Server capability introspection
   - Tool response debugger
   - Request/response logging viewer
   - Performance profiling tools
   - Test utilities for MCP integrations

5. **Quality of Life Features**
   - Command history and favorites
   - Customizable keymaps
   - Telescope integration
   - Snippet generation from responses
   - Session persistence

### Long-term Goals

1. **Community Integration**

   - Server discovery and sharing
   - Tool/resource marketplace
   - Community templates and configs
   - Integration guides and examples

2. **Advanced Features**
   - Multi-server orchestration
   - Response caching and optimization
   - Custom server templates
   - Automated workflow creation
   - Integration with popular Neovim plugins

Your contributions and suggestions are welcome! Feel free to open issues or submit pull requests to help implement these features.

## ⭐ Show Your Support

Give a ⭐️ if this project helped you!

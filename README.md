# MCPHub.nvim

[![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

A powerful Neovim plugin that integrates MCP (Model Context Protocol) servers into your workflow. Configure and manage MCP servers through a centralized config file while providing an intuitive UI for testing tools and resources. Perfect for LLM integration, offering both programmatic API access and interactive testing capabilities through the `:MCPHub` command.

<div align="center">
<p>
<h3>MCP Hub Interface</h3>
<video controls muted src="https://github.com/user-attachments/assets/9e574d2d-358e-4a3e-ae19-d9e85c5dd2f0"></video>
</p>
</div>

## ✨ Features

- Simple single-command interface (`:MCPHub`)
- Interactive UI for testing tools and resources
- Automatic server lifecycle management across multiple Neovim instances
- Smart shutdown handling with configurable delay
- Both sync and async operations supported
- Clean client registration/cleanup
- Comprehensive API for tool and resource access

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",  -- Required for Job and HTTP requests
    },
    build = "npm install -g mcp-hub@latest", -- Installs required mcp-hub npm module
    config = function()
        require("mcphub").setup({
            -- Required options
            port = 3000,  -- Port for MCP Hub server
            config = vim.fn.expand("~/mcpservers.json"),  -- Absolute path to config file

            -- Optional options
            on_ready = function(hub)
                -- Called when hub is ready
            end,
            on_error = function(err)
                -- Called on errors
            end,
            shutdown_delay = 10000, -- Wait 10s before shutting down server after last client exits
            log = {
                level = vim.log.levels.WARN,
                to_file = false,
                file_path = nil,
                prefix = "MCPHub"
            },
        })
    end
}
```

### Requirements

- Neovim >= 0.8.0
- Node.js >= 18.0.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [mcp-hub](https://github.com/ravitemer/mcp-hub) (automatically installed via build command)

## 🚀 Usage

1. Open the MCPHub UI to test tools and monitor server status:

```vim
:MCPHub
```

2. Use the hub instance in your code:

```lua
-- Get hub instance after setup
local mcphub = require("mcphub")

-- Option 1: Use on_ready callback
mcphub.setup({
    port = 3000,
    config = vim.fn.expand("~/mcpservers.json"),
    on_ready = function(hub)
        -- Hub is ready to use here
    end
})

-- Option 2: Get hub instance directly (might be nil if setup in progress)
local hub = mcphub.get_hub_instance()

-- Call a tool (sync)
local response, err = hub:call_tool("server-name", "tool-name", {
    param1 = "value1"
}, {
    return_text = true -- Parse response to LLM-suitable text
})

-- Call a tool (async)
hub:call_tool("server-name", "tool-name", {
    param1 = "value1"
}, {
    return_text = true,
    callback = function(response, err)
        -- Use response
    end
})

-- Access resource (sync)
local response, err = hub:access_resource("server-name", "resource://uri", {
    return_text = true
})

-- Get prompt helpers for system prompts
local prompts = hub:get_prompts({
    use_mcp_tool_example = [[<use_mcp_tool>
<server_name>weather-server</server_name>
<tool_name>get_forecast</tool_name>
<arguments>
{
  "city": "San Francisco",
  "days": 5
}
</arguments>
</use_mcp_tool>]],
    access_mcp_resource_example = [[<access_mcp_resource>
<server_name>weather-server</server_name>
<uri>weather://san-francisco/current</uri>
</access_mcp_resource>]]
})
-- prompts.active_servers: Lists currently active servers
-- prompts.use_mcp_tool: Instructions for tool usage with example
-- prompts.access_mcp_resource: Instructions for resource access with example
```

## 🔌 Extensions

MCPHub.nvim provides extensions that integrate with popular Neovim chat plugins. These extensions allow you to use MCP tools and resources directly within your chat interfaces.

### Available Extensions

- **[CodeCompanion](https://github.com/olimorris/codecompanion.nvim) Integration**: Add MCP capabilities to CodeCompanion
  ```lua
  tools = {
    ["mcp"] = {
      callback = require("mcphub.extensions.codecompanion"),
      description = "Call tools and resources from the MCP Servers",
      opts = {
        user_approval = true,
      },
    },
  }
  ```

See the [extensions/](extensions/) folder for more examples and implementation details.

Note: You can also access the Express server directly at http://localhost:[port]/api

## 🔧 Troubleshooting

1. **Port Issues**

   - If you get `EADDRINUSE` error, kill the existing process:
     ```bash
     lsof -i :[port]  # Find process ID
     kill [pid]       # Kill the process
     ```

2. **Configuration File**

   - Ensure config path is absolute
   - Verify file contains valid JSON with `mcpServers` key
   - Check server-specific configuration requirements

3. **MCP Server Issues**

   - Use [MCP Inspector](https://github.com/modelcontextprotocol/inspector) to verify server operation
   - Check server logs in MCPHub UI (Logs view)

4. **Need Help?**
   - Create a [Discussion](https://github.com/ravitemer/mcphub.nvim/discussions) for questions
   - Open an [Issue](https://github.com/ravitemer/mcphub.nvim/issues) for bugs

## 🔄 How It Works

MCPHub.nvim uses an Express server to manage MCP servers and handle client requests:

1. When `setup()` is called:

   - Checks for mcp-hub command installation
   - Verifies version compatibility
   - Starts mcp-hub with provided port and config file
   - Creates Express server at localhost:[port]

2. After successful setup:

   - Calls on_ready callback with hub instance
   - Hub instance provides REST API interface
   - UI updates in real-time via `:MCPHub` command

3. Express Server Features:

   - Manages MCP server configurations
   - Handles tool execution requests
   - Provides resource access
   - Multi-client support
   - Automatic cleanup

4. When Neovim instances close:
   - Unregister as clients
   - Last client triggers shutdown timer
   - Server waits shutdown_delay seconds before stopping
   - Timer cancels if new client connects

This architecture ensures:

- Consistent server management
- Real-time status monitoring
- Efficient resource usage
- Clean process handling
- Multiple client support

### Architecture Flows

![Server Lifecycle](https://github.com/user-attachments/assets/a26422fe-ba98-4cfc-9cbe-9e3867e1625f)

![Request Flow](https://github.com/user-attachments/assets/319f203f-615b-4de0-846f-fd444498770c)

![Cleanup Flow](https://github.com/user-attachments/assets/0ccec454-6d0c-4460-9b2d-0e597bab2ae9)

![API Flow](https://github.com/user-attachments/assets/5b3fb3d2-aa37-499f-badd-b4cfc1c59e71)

## 👏 Acknowledgements

Thanks to:

- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for inspiring our text highlighting utilities

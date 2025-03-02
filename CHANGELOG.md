# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2025-03-02

### Added

- New UI system with comprehensive views
  - Main view for server status
  - Servers view for tools and resources
  - Config view for settings
  - Logs view for output
  - Help view with quick start guide
- Interactive tool and resource execution interface
  - Parameter validation and type conversion
  - Real-time response display
  - Cursor tracking and highlighting
- CodeCompanion extension support
  - Integration with chat interface
  - Tool and resource access
- Enhanced state management
  - Server output handling
  - Error display with padding
  - Cursor position persistence
- Server utilities
  - Uptime formatting
  - Shutdown delay handling
  - Configuration validation

### Changed

- Improved parameter handling with ordered retrieval
- Enhanced text rendering with pill function
- Better error display with padding adjustments
- Refined UI layout and keymap management
- Updated server output management
- Enhanced documentation with quick start guide
- Upgraded version compatibility with mcp-hub 1.3.0

### Refactored

- Server uptime formatting moved to utils
- Tool execution mode improvements
- Error handling and server output management
- Configuration validation system
- UI rendering system

## [1.2.0] - 2024-02-22

### Added

- Default timeouts for operations (1s for health checks, 30s for tool/resource access)
- API tests for hub instance with examples
- Enhanced error formatting in handlers for better readability

### Changed

- Updated error handling to use simpler string format
- Added support for both sync/async API patterns across all operations
- Improved response processing and error propagation

## [1.1.0] - 2024-02-21

### Added

- Version management utilities with semantic versioning support
- Enhanced error handling with structured error objects
- Improved logging capabilities with file output support
- Callback-based initialization with on_ready and on_error hooks
- Server validation improvements with config file syntax checking
- Streamlined API error handling and response processing
- Structured logging with different log levels and output options
- Better process output handling with JSON parsing

### Changed

- Simplified initialization process by removing separate start_hub call
- Updated installation to use specific mcp-hub version
- Improved error reporting with detailed context

## [1.0.0] - 2024-02-20

### Added

- Initial release of MCPHub.nvim
- Single-command interface (:MCPHub)
- Automatic server lifecycle management
- Async operations support
- Clean client registration/cleanup
- Smart process handling
- Configurable logging
- Full API support for MCP Hub interaction
- Comprehensive error handling
- Detailed documentation and examples
- Integration with lazy.nvim package manager

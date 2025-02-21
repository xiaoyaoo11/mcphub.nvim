# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

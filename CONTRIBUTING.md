# Contributing to MCPHub.nvim

We love your input! We want to make contributing to MCPHub.nvim as easy and transparent as possible.

## Development Prerequisites

- Neovim >= 0.8.0
- Node.js >= 18.0.0 (for mcp-hub)
- Basic knowledge of Lua
- Understanding of asynchronous programming
- Familiarity with Neovim plugin development

## Development Process

1. Fork the repo and create your branch from `main`
2. Install development dependencies:

   ```bash
   # Install mcp-hub globally
   npm install -g mcp-hub

   # Install plenary.nvim (required for development)
   git clone https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
   ```

3. Make your changes
4. Test your changes:
   - Ensure all existing tests pass
   - Add new tests for new functionality
   - Test with different Neovim versions if possible
5. Update documentation if needed
6. Create a pull request

## Lua Style Guide

Please follow these style guidelines for Lua code:

- Use 2 spaces for indentation
- Use snake_case for function and variable names
- Use PascalCase for module names
- Document functions using LuaDoc comments
- Keep lines under 80 characters when possible
- Use local variables unless global scope is needed
- Add type annotations in comments when helpful

Example:

```lua
--- Starts the MCP Hub server
---@param opts table Configuration options
---@return boolean success
local function start_server(opts)
  local config = opts or {}
  -- Implementation
end
```

## Documentation

- Update README.md for user-facing changes
- Add docstrings to new functions
- Update vim docs in doc/mcphub.txt if applicable
- Include examples for new features
- Document any breaking changes

## Testing

- Add tests for new features in `tests/`
- Run tests with:
  ```lua
  require('plenary.test_harness').test_directory('tests')
  ```
- Test both synchronous and asynchronous code paths
- Include error cases in tests

## Common Tasks

### Adding a New Feature

1. Create feature branch
2. Implement the feature
3. Add tests
4. Update documentation
5. Submit pull request

### Fixing a Bug

1. Create bug fix branch
2. Add test case that reproduces the bug
3. Fix the bug
4. Verify all tests pass
5. Submit pull request

### Adding Documentation

1. Update relevant .md files
2. Update vim help docs if needed
3. Include examples
4. Submit pull request

## Pull Request Process

1. Update the README.md with details of changes if needed
2. Update the CHANGELOG.md with notes under "Unreleased" section
3. Update vim help documentation if needed
4. The PR will be merged once you have the sign-off of maintainers

## Community

- Follow our [Code of Conduct](./CODE_OF_CONDUCT.md)
- Be respectful of different viewpoints
- Accept constructive criticism
- Focus on what is best for the community

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

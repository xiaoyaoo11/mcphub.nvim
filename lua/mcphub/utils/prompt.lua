---@brief [[
--- Utility functions for generating MCP system prompts.
--- Parts of the prompts are inspired from RooCode repository:
--- https://github.com/RooVetGit/Roo-Code
---@brief ]]
local M = {}

local function get_header()
    return [[
MCP SERVERS

The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.

# Connected MCP Servers]]
end

local function format_tools(tools)
    if not tools or #tools == 0 then
        return ""
    end

    local result = "\n\n### Available Tools"
    for i, tool in ipairs(tools) do
        result = result .. string.format("\n\n- %s: %s", tool.name, tool.description or "")
        if tool.inputSchema then
            result = result .. "\n    Input Schema:\n    " .. vim.inspect(tool.inputSchema):gsub("\n", "\n    ")
        end
    end
    return result
end

local function format_resources(resources)
    if not resources or #resources == 0 then
        return ""
    end

    local result = "\n\n### Available Resources"
    for i, resource in ipairs(resources) do
        result = result .. "\n\n" .. vim.inspect(resource)
    end
    return result
end

--- Get the use_mcp_tool section of the prompt
---@param example? string Optional custom XML example block
---@return string The formatted prompt section
function M.get_use_mcp_tool_prompt(example)
    local default_example = [[<use_mcp_tool>
<server_name>weather-server</server_name>
<tool_name>get_forecast</tool_name>
<arguments>
{
  "city": "San Francisco",
  "days": 5
}
</arguments>
</use_mcp_tool>]]

    return string.format([[
## use_mcp_tool

Description: Request to use a tool provided by a connected MCP server. Each MCP server can provide multiple tools with different capabilities. Tools have defined input schemas that specify required and optional parameters.
Parameters:
- server_name: (required) The name of the MCP server providing the tool
- tool_name: (required) The name of the tool to execute
- arguments: (required) A JSON object containing the tool's input parameters, following the tool's input schema

Example: Requesting to use an MCP tool

%s]], example or default_example)
end

--- Get the access_mcp_resource section of the prompt
---@param example? string Optional custom XML example block
---@return string The formatted prompt section
function M.get_access_mcp_resource_prompt(example)
    local default_example = [[<access_mcp_resource>
<server_name>weather-server</server_name>
<uri>weather://san-francisco/current</uri>
</access_mcp_resource>]]

    return string.format([[
## access_mcp_resource

Description: Request to access a resource provided by a connected MCP server. Resources represent data sources that can be used as context, such as files, API responses, or system information.
Parameters:
- server_name: (required) The name of the MCP server providing the resource
- uri: (required) The URI identifying the specific resource to access

Example: Requesting to access an MCP resource

%s]], example or default_example)
end

function M.get_active_servers_prompt(servers)
    local prompt = get_header()

    if not servers or #servers == 0 then
        return prompt .. "\n\n(No MCP servers connected)"
    end

    prompt = prompt .. "\n\nWhen a server is connected, you can use the server's tools via the `use_mcp_tool` tool, " ..
                 "and access the server's resources via the `access_mcp_resource` tool."

    for _, server in ipairs(servers) do
        if server.capabilities and ((server.capabilities.tools and #server.capabilities.tools > 0) or
            (server.capabilities.resources and #server.capabilities.resources > 0)) then
            -- Add server section
            prompt = prompt .. string.format("\n\n## %s", server.name)
            prompt = prompt .. format_tools(server.capabilities.tools)
            prompt = prompt .. format_resources(server.capabilities.resources)
        end
    end

    return prompt
end

function M.parse_tool_response(response)
    if response == nil then
        return ""
    end
    local result = response.result or {}
    local output = ""
    -- parse tool response
    local isError = result.isError or false
    local content = {}
    for _, v in ipairs(result.content or {}) do
        local type = v.type
        -- TODO:handle other types
        if type == "text" then
            table.insert(content, string.format([[<text>
%s
</text>]], v.text))
        end
        output = string.format([[<content>
%s
</content>]], table.concat(content, "\n"))
        if isError then
            output = string.format('The tool run failed with error.\n%s', output)
        end
        output = string.format([[<result>
%s
</result>]], output)
    end
    return output
end

function M.parse_resource_response(response)
    if response == nil then
        return ""
    end
    local result = response.result or {}
    local output = ""
    local contents = {}
    for _, v in ipairs(result.contents or {}) do
        local uri = v.uri or ""
        local text = v.text or ""
        local mimeType = v.mimeType or ""
        table.insert(contents, string.format([[
<resource>
<uri>%s</uri>
<text>%s</text>
</resource>
]], uri, text))
    end
    output = string.format([[
<contents>
%s
</contents>
]], table.concat(contents, "\n"))
    output = string.format([[
<result>
%s
</result>]], output)
    return output
end

return M

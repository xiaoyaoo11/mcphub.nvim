local M = {}
local cb = function(prompt, mode)
    mode = mode or "planning"
    local root = require("avante.utils").get_project_root()
    local path = string.format("%s/%s.avanterules", root, mode)
    if prompt then
        -- write to file
        local file = io.open(path, "w")
        file:write(prompt)
        file:close()
    end
end

function M.mcp_tool(mode)
    local ok, mcphub = pcall(require, "mcphub")
    if ok then
        -- this updates mode.avanterules file everytime servers are updated so that avante adds this file to system prompt.
        -- sadly, this is the only way to update avante prompt.
        -- require("avante.config").override({system_prompt= prompt}) is not working.
        mcphub.on("servers_updated", function(data)
            local prompt = data.prompt or ""
            cb(prompt, mode)
        end)
    end
    return {
        name = "mcp",
        description = "The Model Context Protocol (MCP) enables communication with locally running MCP servers that provide additional tools and resources to extend your capabilities. This tool calls mcp tools and resources on the mcp servers.",
        param = {
            type = "table",
            fields = {
                {
                    name = "action",
                    description = "Action to perform: one of `access_mcp_resource` or `use_mcp_tool`",
                    type = "string",
                },
                {
                    name = "server_name",
                    description = "Name of the MCP server",
                    type = "string",
                },
                {
                    name = "uri",
                    description = "URI of the resource to access",
                    type = "string",
                },
                {
                    name = "tool_name",
                    description = "Name of the tool to call",
                    type = "string",
                },
                {
                    name = "arguments",
                    description = "Arguments for the tool",
                    type = "object",
                },
            },
        },
        returns = {
            {
                name = "result",
                description = "Result from the MCP tool",
                type = "string",
            },
            {
                name = "error",
                description = "Error message if the call failed",
                type = "string",
                optional = true,
            },
        },
        func = function(params)
            local hub = require("mcphub").get_hub_instance()
            if not hub then
                return nil, "MCP Hub not initialized"
            end

            if not params.server_name then
                return nil, "server_name is required"
            end
            if params.action == "access_mcp_resource" and not params.uri then
                return nil, "uri is required"
            end

            if params.action == "use_mcp_tool" and not params.tool_name then
                return nil, "tool_name is required"
            end

            if params.action == "access_mcp_resource" then
                local res, err = hub:access_resource(params.server_name, params.uri, {
                    return_text = true,
                })
                if err or not res then
                    return nil, err
                elseif res then
                    return res
                end
            elseif params.action == "use_mcp_tool" then
                local res, err = hub:call_tool(params.server_name, params.tool_name, params.arguments, {
                    return_text = true,
                })
                if err or not res then
                    return nil, err
                elseif res then
                    return res
                end
            else
                return nil, "Invalid action type"
            end
        end,
    }
end

return M

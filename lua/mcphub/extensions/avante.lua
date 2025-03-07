local M = {}
local function update_avanterules(prompt, mode, cwd)
    mode = mode or "planning"
    local root = require("avante.utils").get_project_root()
    if cwd then
        root = type(cwd) == "function" and cwd() or vim.fn.expand(cwd)
    end
    if not root then
        vim.notify("Avante: Project root not found", "error")
        return
    end
    local path = string.format("%s/%s.avanterules", root, mode)
    vim.notify("MCPHUB: Updating avanterules at " .. path, "info")

    -- Do nothing if no prompt
    if not prompt then
        return
    end

    -- Try to read existing file
    local file = io.open(path, "r")
    if file then
        -- File exists, check for marker
        local content = file:read("*all")
        file:close()

        -- Look for jinja section markers
        local start_marker = "{% block mcp_servers %}"
        local end_marker = "{% endblock %}"

        local start_pos = content:find(start_marker, 1, true)
        if start_pos then
            -- Found start marker, now find end marker after it
            local end_pos = content:find(end_marker, start_pos, true)
            if end_pos then
                -- Found both markers, replace content between them
                local prefix = content:sub(1, start_pos - 1)
                local suffix = content:sub(end_pos + #end_marker)
                local new_content = prefix .. start_marker .. "\n" .. prompt .. "\n" .. end_marker .. suffix
                file = io.open(path, "w")
                file:write(new_content)
                file:close()
            else
                -- End marker not found, treat as no markers
                file = io.open(path, "w")
                file:write(start_marker .. "\n" .. prompt .. "\n" .. end_marker)
                file:close()
            end
        else
            -- No marker found, write template and prompt
            file = io.open(path, "w")
            file:write(start_marker .. "\n" .. prompt .. "\n" .. end_marker)
            file:close()
        end
    else
        -- File doesn't exist, create new
        file = io.open(path, "w")
        file:write("{% block mcp_servers %}\n" .. prompt .. "\n{% endblock %}")
        file:close()
    end
end

function M.mcp_tool(mode, cwd)
    local ok, mcphub = pcall(require, "mcphub")
    if ok then
        -- Updates mode.avanterules file everytime servers are updated so avante adds this file to system prompt.
        -- require("avante.config").override({system_prompt= prompt}) is not working, this is currently the only way.
        mcphub.on("servers_updated", function(data)
            local prompt = data.prompt or ""
            update_avanterules(prompt, mode, cwd)
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

---@brief [[
--- Utility functions for Servers view
---@brief ]]
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local highlights = require("mcphub.utils.highlights")

local M = {}

--- Format duration in seconds to human readable string
---@param seconds number Duration in seconds
---@return string Formatted duration
function M.format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Get ordered list of parameters from schema
---@param tool_info table Tool information with schema
---@param current_values table<string, string> Current parameter values
---@return table[] List of parameter objects
function M.get_ordered_params(tool_info, current_values)
    if not tool_info or not tool_info.inputSchema or not tool_info.inputSchema.properties then
        return {}
    end

    local params = {}
    for name, prop in pairs(tool_info.inputSchema.properties) do
        table.insert(params, {
            name = name,
            type = prop.type,
            description = prop.description,
            required = vim.tbl_contains(tool_info.inputSchema.required or {}, name),
            default = prop.default,
            value = current_values[name]
        })
    end

    -- Sort by required first, then name
    table.sort(params, function(a, b)
        if a.required ~= b.required then
            return a.required
        end
        return a.name < b.name
    end)

    return params
end

--- Validate all required parameters are filled
---@param tool_info table Tool information with schema
---@param values table<string, string> Current parameter values
---@return boolean, string|nil is_valid, error_message
function M.validate_all_params(tool_info, values)
    if not tool_info or not tool_info.inputSchema then
        return false, "No parameters to validate"
    end

    local errors = {}
    local params = M.get_ordered_params(tool_info, values)

    for _, param in ipairs(params) do
        if param.required and (not values[param.name] or values[param.name] == "") then
            errors[param.name] = "Required parameter"
        end
    end

    if next(errors) then
        return false, "Some required parameters are missing", errors
    end

    return true, nil, {}
end

--- Render server information
---@param server table Server data
---@param line_offset number Current line number offset
---@return NuiLine[] lines, number new_offset
function M.render_server(server, line_offset)
    local lines = {}

    local current_line = line_offset + 1
    -- Server header
    local title = NuiLine():append("╭─ ", Text.highlights.muted):append(" " .. server.name .. " ",
        Text.highlights.header_btn)
    table.insert(lines, Text.pad_line(title))

    -- Server details
    if server.uptime then
        local uptime = NuiLine():append("│ ", Text.highlights.muted):append("Uptime: ", Text.highlights.muted):append(
            M.format_uptime(server.uptime), Text.highlights.info)
        table.insert(lines, Text.pad_line(uptime))
    end

    -- Capabilities
    if server.capabilities then
        -- Tools
        if #server.capabilities.tools > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Tools: ", Text.highlights.header)))

            for _, tool in ipairs(server.capabilities.tools) do
                -- Tool name
                local tool_line = NuiLine():append("│  • ", Text.highlights.muted):append(tool.name,
                    Text.highlights.success)
                table.insert(lines, Text.pad_line(tool_line))

                -- Track tool line number at the actual buffer position
                tool._line_nr = line_offset + #lines

                -- Tool description
                if tool.description then
                    for _, desc_line in ipairs(Text.multiline(tool.description, highlights.groups.muted)) do
                        local desc = NuiLine():append("│    ", Text.highlights.muted):append(desc_line,
                            Text.highlights.muted)
                        table.insert(lines, Text.pad_line(desc))
                    end
                end
            end
        end

        -- Resources
        if #server.capabilities.resources > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Resources: ", Text.highlights.header)))
            for _, resource in ipairs(server.capabilities.resources) do
                local res_line = NuiLine():append("│  • ", Text.highlights.muted):append(resource.name,
                    Text.highlights.success):append(" (", Text.highlights.muted):append(resource.mimeType,
                    Text.highlights.info):append(")", Text.highlights.muted)
                table.insert(lines, Text.pad_line(res_line))
            end
        end
    end

    -- Server footer
    table.insert(lines, Text.pad_line(NuiLine():append("╰─", Text.highlights.muted)))
    table.insert(lines, Text.empty_line())

    return lines, line_offset + #lines
end

--- Render parameter input form
---@param tool_info table Tool information with schema
---@param state table Current parameter state (values, errors, etc)
---@return NuiLine[] lines, table<number, string> param_lines, number submit_line
function M.render_params_form(tool_info, state)
    local lines = {}
    local param_lines = {}

    table.insert(lines, Text.pad_line(" Input Params: ", Text.highlights.header))
    table.insert(lines, Text.empty_line())

    -- Parameters
    local params = M.get_ordered_params(tool_info, state.values or {})
    for _, param in ipairs(params) do
        -- Parameter name
        local name_line = NuiLine():append(param.required and "* " or "  ", Text.highlights.error):append(param.name,
            Text.highlights.success)

        if param.type then
            name_line:append(" (", Text.highlights.muted):append(param.type, Text.highlights.muted):append(")",
                Text.highlights.muted)
        end

        table.insert(lines, Text.pad_line(name_line))
        -- add description
        if param.description then
            for _, desc_line in ipairs(Text.multiline(param.description, Text.highlights.muted)) do
                local desc = NuiLine():append("  ", Text.highlights.muted):append(desc_line, Text.highlights.muted)
                table.insert(lines, Text.pad_line(desc))
            end
        end

        -- Value input (store line number for cursor detection)
        local value = (state.values or {})[param.name]
        local input_line = NuiLine():append("  ", Text.highlights.title):append("> ", Text.highlights.success):append(
            value or "", Text.highlights.info)
        table.insert(lines, Text.pad_line(input_line))
        param_lines[#lines] = param.name

        -- Error if any
        if state.errors and state.errors[param.name] then
            table.insert(lines, Text.pad_line(
                NuiLine():append("  ⚠ ", Text.highlights.error)
                    :append(state.errors[param.name], Text.highlights.error)))
        end
        table.insert(lines, Text.empty_line())
    end

    -- Submit button (store line number for cursor detection)
    table.insert(lines, Text.empty_line())
    local submit_line = NuiLine():append("  ", Text.highlights.title):append(" Submit ", Text.highlights.success_fill)
    table.insert(lines, Text.pad_line(submit_line))
    local submit_line_num = #lines

    -- Submit error
    if state.submit_error then
        table.insert(lines, Text.empty_line())
        table.insert(lines, Text.pad_line(
            NuiLine():append("⚠ ", Text.highlights.error):append(state.submit_error, Text.highlights.error)))
    end

    -- Execution result
    if state.result then
        table.insert(lines, Text.empty_line())
        table.insert(lines, Text.pad_line(NuiLine():append(" Result: ", Text.highlights.header)))
        table.insert(lines, Text.empty_line())
        local result_json = state.result

        if type(result_json) == "table" then
            result_json = vim.fn.json_encode(result_json)
        end
        vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(result_json, Text.highlights.info)))
    end

    return lines, param_lines, submit_line_num
end

return M

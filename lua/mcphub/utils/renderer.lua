local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")

local M = {}

-- Format timestamp (could be Unix timestamp or ISO string)
local function format_time(timestamp)
    -- For Unix timestamps
    return os.date("%H:%M:%S", math.floor(timestamp / 1000))
end

function M.render_hub_errors(errors)
    local lines = {}
    if #errors > 0 then
        -- Section header
        table.insert(lines, Text.section("Recent Issues", {}, true)[1])

        for i = 1, #errors, 1 do
            local err = errors[i]
            local error_lines = Text.multiline(err.message, Text.highlights.error)
            local first_line = NuiLine():append("• ", Text.highlights.error):append(error_lines[1])
            error_lines[1] = first_line
            vim.list_extend(lines, vim.tbl_map(Text.pad_line, error_lines))

            -- Add error details if any
            if err.details and next(err.details) then
                local errlines = vim.tbl_map(function(t)
                    return Text.pad_line(Text.pad_line(t))
                end, Text.multiline(vim.inspect(err.details), Text.highlights.muted))
                vim.list_extend(lines, errlines)
            end
        end

        table.insert(lines, Text.empty_line())
    end
    return lines
end

function M.render_server_entries(entries, add_placeholder)
    add_placeholder = add_placeholder or true
    local lines = {}

    local type_icons = {
        info = "● ",
        warn = "⚠ ",
        error = "✖ ",
        debug = "◆ "
    }

    local type_hl = {
        info = Text.highlights.info,
        warn = Text.highlights.warning,
        error = Text.highlights.error,
        debug = Text.highlights.muted
    }
    if #entries > 0 then
        for _, entry in ipairs(entries) do
            if entry.timestamp and entry.message then
                local line = NuiLine()
                -- Add timestamp
                line:append(string.format("[%s] ", format_time(entry.timestamp)), Text.highlights.muted)

                -- Add type icon and message
                line:append(type_icons[entry.type] or "• ", type_hl[entry.type])
                local code = entry.code
                if code then
                    line:append(string.format("[Code: %s] ", code), Text.highlights.muted)
                end
                line:append(entry.message, type_hl[entry.type])
                table.insert(lines, Text.pad_line(line))

                -- Add extra data if available
                -- TODO: show any related data on exapnding

            end
        end
    else
        if add_placeholder then
            table.insert(lines, Text.pad_line("No logs available", Text.highlights.muted))
        end
    end
    return lines
end

return M

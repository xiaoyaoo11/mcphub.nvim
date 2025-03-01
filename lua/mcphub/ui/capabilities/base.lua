local highlights = require("mcphub.utils.highlights").groups
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")

---@class CapabilityHandler
---@field server_name string Name of the server this capability belongs to
---@field info table Raw capability info from the server
---@field state table Current state of the capability execution
---@field interactive_lines { line: number, type: string, context: any}[] List of interactive lines
local CapabilityHandler = {
    type = nil -- to be set by subclasses
}
CapabilityHandler.__index = CapabilityHandler

function CapabilityHandler:new(server_name, capability_info, view)
    local handler = setmetatable({
        server_name = server_name,
        info = capability_info,
        view = view,
        state = {
            is_executing = false,
            result = nil,
            error = nil
        },
        interactive_lines = {}
    }, self)
    return handler
end

-- Line tracking for interactivity
function CapabilityHandler:track_line(line_nr, type, context)
    table.insert(self.interactive_lines, {
        line = line_nr,
        type = type,
        context = context
    })
end

function CapabilityHandler:clear_line_tracking()
    self.interactive_lines = {}
end

function CapabilityHandler:get_line_info(line_nr)
    for _, tracked in ipairs(self.interactive_lines) do
        if tracked.line == line_nr then
            return tracked.type, tracked.context
        end
    end
    return nil, nil
end

-- Common highlighting
function CapabilityHandler:handle_cursor_move(view, line)
    local type, context = self:get_line_info(line)
    if not type then
        return
    end

    if type == "submit" and not self.state.is_executing then
        view.cursor_highlight = vim.api.nvim_buf_set_extmark(view.ui.buffer, view.hover_ns, line - 1, 0, {
            line_hl_group = highlights.active_item,
            virt_text = {{"Press <CR> to submit", highlights.muted}},
            virt_text_pos = "eol"
        })
    elseif type == "input" then
        view.cursor_highlight = vim.api.nvim_buf_set_extmark(view.ui.buffer, view.hover_ns, line - 1, 0, {
            line_hl_group = highlights.active_item,
            virt_text = {{"Press <CR> to edit", highlights.muted}},
            virt_text_pos = "eol"
        })
    end
end

-- Input handling
function CapabilityHandler:handle_input(prompt, default, callback)
    vim.ui.input({
        prompt = prompt,
        default = default or ""
    }, function(input)
        if input ~= nil then -- Only handle if not cancelled
            callback(input)
        end
    end)
end

-- Common section rendering utilities
function CapabilityHandler:render_section_start(title, highlight)
    local lines = {}
    table.insert(lines, Text.pad_line(
        NuiLine():append("╭─ ", highlights.muted):append(" " .. title .. " ", highlight or highlights.header)))
    return lines
end

function CapabilityHandler:render_section_content(content, indent_level)
    local lines = {}
    local padding = string.rep(" ", indent_level or 1)
    for _, line in ipairs(content) do
        local rendered_line = NuiLine()
        if type(line) == "string" then
            rendered_line:append("│", highlights.muted):append(padding, highlights.muted):append(line)
        else
            rendered_line:append("│", highlights.muted):append(padding, highlights.muted):append(line)
        end
        table.insert(lines, Text.pad_line(rendered_line))
    end
    return lines
end

function CapabilityHandler:render_section_end()
    return {Text.pad_line(NuiLine():append("╰─", highlights.muted):append(" ", highlights.muted))}
end

-- Common result rendering
function CapabilityHandler:render_result()
    if not self.state.result then
        return {}
    end

    local lines = {}
    table.insert(lines, Text.pad_line(NuiLine())) -- Empty line
    vim.list_extend(lines, self:render_section_start("Result"))

    local result_json = self.state.result
    if type(result_json) == "table" then
        result_json = vim.fn.json_encode(result_json)
    end

    for _, line in ipairs(Text.multiline(result_json, highlights.info)) do
        vim.list_extend(lines, self:render_section_content({line}, 1))
    end

    vim.list_extend(lines, self:render_section_end())
    return lines
end

-- Error handling
function CapabilityHandler:handle_response(response, err)
    self.state.is_executing = false
    if err then
        vim.notify(string.format("%s execution failed: %s", self.type, err), vim.log.levels.ERROR)
        self.state.error = err
    else
        vim.notify(string.format("%s executed successfully", self.type), vim.log.levels.INFO)
        self.state.result = response
        self.state.error = nil
    end
end

-- Abstract methods to be implemented by subclasses
function CapabilityHandler:execute()
    error(string.format("execute() not implemented for capability type: %s", self.type))
end

function CapabilityHandler:handle_action(line)
    error(string.format("handle_action() not implemented for capability type: %s", self.type))
end

function CapabilityHandler:render(line_offset)
    error(string.format("render() not implemented for capability type: %s", self.type))
end

return CapabilityHandler

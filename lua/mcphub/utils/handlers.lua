local log = require("mcphub.utils.log")
local Error = require("mcphub.errors")

local M = {}

--- Process handlers for server process management
M.ProcessHandlers = {
    --- Handle server process stdout/stderr
    --- @param data string Raw output data
    --- @param opts table Options including callbacks
    --- @return boolean handled Whether the data was handled
    handle_output = function(data, hub, opts)
        if not data then
            return ""
        end

        local ok, parsed = pcall(vim.json.decode, data)
        if not ok then
            -- Not JSON data, let caller handle raw output
            return data
        end

        -- Handle structured server logs
        if parsed.type == "error" then
            local error_obj = Error("SERVER", parsed.code or Error.Types.SERVER.CONNECTION, parsed.message, parsed.data)
            log.error(tostring(error_obj))
            hub:handle_server_error(tostring(error_obj), opts)
            -- Mark as handled since it's an error
            return true
        end

        -- Log other structured messages at appropriate level
        if parsed.type == "info" then
            log.info({
                code = parsed.code or "SERVER_INFO",
                message = parsed.message,
                data = parsed.data
            })
        elseif parsed.type == "warn" then
            log.warn({
                code = parsed.code or "SERVER_WARN",
                message = parsed.message,
                data = parsed.data
            })
        elseif parsed.type == "debug" then
            log.debug({
                code = parsed.code or "SERVER_DEBUG",
                message = parsed.message,
                data = parsed.data
            })
        end

        -- Handle ready state (backward compatibility)
        if (parsed.type == "info" and parsed.message == "MCP_HUB_STARTED" and parsed.data) and parsed.data.status ==
            "ready" then
            hub:handle_server_ready(opts)
            return true
        end

        return true
    end
}

--- API response handlers
M.ResponseHandlers = {
    --- Process API errors and create structured error objects
    --- @param error table|string Error from API
    --- @param context table Additional context to include
    --- @return MCPError Structured error object
    process_error = function(error, context)
        if type(error) == "table" then
            if error.code and error.message then
                -- Already structured error
                if context then
                    error.data = vim.tbl_extend("force", error.data or {}, context)
                end
                return Error("SERVER", Error.Types.SERVER.API_ERROR, vim.inspect(error), context)
            end
            -- Table error without proper structure
            return Error("SERVER", Error.Types.SERVER.API_ERROR, vim.inspect(error), context)
        end
        -- String error
        return Error("SERVER", Error.Types.SERVER.API_ERROR, error, context)
    end,

    --- Handle curl specific errors
    --- @param response table Curl response
    --- @param context table Request context
    --- @return MCPError|nil error Structured error if any
    handle_curl_error = function(response, context)
        if not response then
            return Error("SERVER", Error.Types.SERVER.CURL_ERROR, "No response from server", context)
        end

        if response.exit ~= 0 then
            local error_code = ({
                [7] = Error.Types.SERVER.CONNECTION,
                [28] = Error.Types.SERVER.TIMEOUT
            })[response.exit] or Error.Types.SERVER.CURL_ERROR

            local error_msg = ({
                [7] = "Connection refused - Server not running",
                [28] = "Request timed out"
            })[response.exit] or string.format("Request failed (code %d)", response.exit)

            return Error("SERVER", error_code, error_msg, vim.tbl_extend("force", context, {
                exit_code = response.exit
            }))
        end

        return nil
    end,

    --- Handle HTTP error responses
    --- @param response table HTTP response
    --- @param context table Request context
    --- @return MCPError|nil error Structured error if any
    handle_http_error = function(response, context)
        if response.status < 400 then
            return nil
        end

        local ok, parsed = pcall(vim.fn.json_decode, response.body)
        if ok and parsed.error then
            return M.ResponseHandlers.process_error(parsed.error, context)
        end

        return Error("SERVER", Error.Types.SERVER.API_ERROR, string.format("Server error (%d)", response.status),
            vim.tbl_extend("force", context, {
                status = response.status,
                body = response.body
            }))
    end,

    --- Parse JSON response
    --- @param response string Raw response body
    --- @param context table Request context
    --- @return table|nil result Parsed response or nil
    --- @return MCPError|nil error Structured error if any
    parse_json = function(response, context)
        if not response then
            return nil, Error("SERVER", Error.Types.SERVER.API_ERROR, "Empty response from server", context)
        end

        local ok, decoded = pcall(vim.fn.json_decode, response)
        if not ok then
            return nil,
                Error("SERVER", Error.Types.SERVER.API_ERROR, "Invalid response: Not JSON",
                    vim.tbl_extend("force", context, {
                        body = response
                    }))
        end

        return decoded, nil
    end
}

return M

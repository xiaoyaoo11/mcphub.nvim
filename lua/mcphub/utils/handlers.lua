local log = require("mcphub.utils.log")

local M = {}

--- Create structured error object
--- @param message string Error message
--- @param code string Error code
--- @param data? table Additional error data
--- @return string error Structured error object
local function create_error(message, code, data)
  -- return vim.inspect({
  --   code = code,
  --   message = message,
  --   data = data or {}
  -- })
  return string.format("%s: %s", code, message)
end

--- Process handlers for server process management
M.ProcessHandlers = {
  --- Handle server process stdout/stderr
  --- @param data string Raw output data
  --- @param opts table Options including callbacks
  --- @return boolean handled Whether the data was handled
  handle_output = function(data, opts)
    if not data then
      return false
    end

    local ok, parsed = pcall(vim.json.decode, data)
    if not ok then
      -- Only log raw stderr as error
      -- if data:match("^%s*[{[]") then
      -- Looks like JSON but failed to parse
      log.error(create_error("Failed to parse server output", "INVALID_SERVER_JSON", {
        output = data
      }))
      -- end
      return false
    end

    -- Handle structured server logs
    if parsed.type == "error" then
      log.error(create_error(parsed.message, parsed.code or "SERVER_ERROR", parsed.data))
      if opts.on_error then
        opts.on_error(create_error(parsed.message, parsed.code or "SERVER_ERROR", parsed.data))
      end
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
    if (parsed.type == "info" and parsed.message == "MCP_HUB_STARTED" and parsed.data) and parsed.data.status == "ready" then
      if opts.on_ready then
        opts.on_ready()
      end
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
  --- @return string Structured error object
  process_error = function(error, context)
    if type(error) == "table" then
      if error.code and error.message then
        -- Already structured error
        if context then
          error.data = vim.tbl_extend("force", error.data or {}, context)
        end
        return create_error(vim.inspect(error), context.code or "API_ERROR", context)
      end
      -- Table error without proper structure
      return create_error(vim.inspect(error), context.code or "API_ERROR", context)
    end
    -- String error
    return create_error(error, context.code or "API_ERROR", context)
  end,

  --- Handle curl specific errors
  --- @param response table Curl response
  --- @param context table Request context
  --- @return table|nil error Structured error if any
  handle_curl_error = function(response, context)
    if not response then
      return create_error("No response from server", "NETWORK_ERROR", context)
    end

    if response.exit ~= 0 then
      local error_code = ({
        [7] = "CONNECTION_REFUSED",
        [28] = "REQUEST_TIMEOUT"
      })[response.exit] or "REQUEST_FAILED"

      local error_msg = ({
        [7] = "Connection refused - Server not running",
        [28] = "Request timed out"
      })[response.exit] or string.format("Request failed (code %d)", response.exit)

      return create_error(error_msg, error_code, vim.tbl_extend("force", context, {
        exit_code = response.exit
      }))
    end

    return nil
  end,

  --- Handle HTTP error responses
  --- @param response table HTTP response
  --- @param context table Request context
  --- @return table|nil error Structured error if any
  handle_http_error = function(response, context)
    if response.status < 400 then
      return nil
    end

    local ok, parsed = pcall(vim.fn.json_decode, response.body)
    if ok and parsed.error then
      return M.ResponseHandlers.process_error(parsed.error, context)
    end

    return create_error(string.format("Server error (%d)", response.status), "HTTP_ERROR",
      vim.tbl_extend("force", context, {
        status = response.status,
        body = response.body
      }))
  end,

  --- Parse JSON response
  --- @param response string Raw response body
  --- @param context table Request context
  --- @return table|nil result Parsed response or nil
  --- @return table|nil error Structured error if any
  parse_json = function(response, context)
    if not response then
      return nil, create_error("Empty response from server", "EMPTY_RESPONSE", context)
    end

    local ok, decoded = pcall(vim.fn.json_decode, response)
    if not ok then
      return nil, create_error("Invalid response: Not JSON", "INVALID_JSON", vim.tbl_extend("force", context, {
        body = response
      }))
    end

    return decoded, nil
  end
}

return M

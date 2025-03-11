--[[ MCPHub image cache utilities ]]
local M = {}

-- Cache directory
M.cache_dir = vim.fn.stdpath("cache") .. "/mcphub/images"

--- Get unique filename based on content hash
---@param data string Base64 encoded image data
---@param mime_type string MIME type of the image
---@return string filename
local function get_unique_filename(data, mime_type)
    local hash = vim.fn.sha256(data)
    local ext = mime_type:match("image/(%w+)") or "bin"
    return string.format("%s.%s", hash, ext)
end

--- Save image to temp file and return file path
---@param data string Base64 encoded image data
---@param mime_type string MIME type of the image
---@return string filepath Path to saved file
function M.save_image(data, mime_type)
    local filename = get_unique_filename(data, mime_type)
    local filepath = M.cache_dir .. "/" .. filename

    -- Save file if it doesn't exist
    if not vim.loop.fs_stat(filepath) then
        local file = io.open(filepath, "wb")
        if file then
            file:write(vim.base64.decode(data))
            file:close()
        end
    end

    return filepath
end

--- Clean all cached images
function M.cleanup()
    -- Get all files in the cache directory
    local files = vim.fn.glob(M.cache_dir .. "/*", true, true)
    for _, file in ipairs(files) do
        vim.fn.delete(file)
    end
end

--- Initialize image cache
function M.setup()
    -- Create cache directory if it doesn't exist
    vim.fn.mkdir(M.cache_dir, "p")

    -- Setup cleanup on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("mcphub_image_cache", { clear = true }),
        callback = function()
            M.cleanup()
        end,
    })
end

return M

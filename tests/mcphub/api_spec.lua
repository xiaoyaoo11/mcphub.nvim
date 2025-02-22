local hub = require("mcphub").get_hub_instance()

if not hub then
  print("Failed to get hub instance")
  return
end

-- get servers
local response = hub:get_servers()
for _, server in ipairs(response.servers) do
  print(server.name)
end

--call tool
local res, err = hub:call_tool("fetch", "fetch", { url = "https://www.google.com" })
if err then
  print("Error: ", err)
else
  print("Success: ", vim.inspect(res))
end

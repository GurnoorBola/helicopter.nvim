local M = {}

local Agent = require("helicopter.agent")

M._servers = {}

---@param cmd string[]
---@return Server
function M.start_server(cmd)
	local server = Agent.Server:new(cmd)
	local id = server:start()
	---@private
	M._active = server
	---@private
	M._servers[id] = server
	return server
end

---@param id? number
---@return Server
function M.get_server(id)
	if id then
		return M._servers[id]
	end
	if not M._active then
		error("Error: No server started")
	end
	return M._active
end

return M

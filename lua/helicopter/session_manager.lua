local Servers = require("helicopter.servers")
local Session = require("helicopter.agent").Session
local M = {}

-- Managed Sessions are an abstraction for sessions that provide convenience features such as storing chat history
-- unloading stale session history from memory, handling presistance, etc
-- Prefer managed sessions over raw sessions for most use cases

---@class ManagedSession
---@field name string
---@field cwd string
---@field history table
---@field stale boolean
---@field private session Session
local ManagedSession = {}

---@package
---@param name string
---@param cwd string
---@param session Session
---@return ManagedSession
function ManagedSession:new(name, cwd, session)
	---@type ManagedSession
	local new_session_data = {
		name = name,
		cwd = cwd,
		history = {},
		stale = false,
		session = session,
	}
	setmetatable(new_session_data, { __index = self })
	for _, update_type in pairs(Session.UpdateType) do
		session:on_session_update(update_type, function(json_response)
			new_session_data:handle_update(json_response)
		end)
	end
	return new_session_data
end

---@package
---@param session_update JsonObject
function ManagedSession:handle_update(session_update)
	-- TODO: coalesce message chunks and other updates
	-- clean up formatting instead of insering SessionUpdate directly

	table.insert(self.history, session_update)
	-- print(self.history[#self.history].sessionUpdate)
end

---@param type UpdateType
---@param callback Callback
function ManagedSession:on_update(type, callback)
	self.session:on_session_update(type, function(json_response)
		self:handle_update(json_response)
		callback(json_response)
	end)
end

-- TODO:

---@param prompt JsonObject
---@param callback? Callback
---@return ManagedSession
function ManagedSession:prompt(prompt, callback)
	self.session:prompt(prompt, callback)
	return self
end

M.session_map = {}

---@param name string
---@param cwd string
---@param callback? Callback
---@return ManagedSession
function M.new_session(name, cwd, callback)
	local server = Servers.get_server()
	local session = server:new_session({
		cwd = cwd,
		mcpServers = {
			-- TODO: configure mcp servers to give new sessions
		},
	}, callback)
	local session_data = ManagedSession:new(name, cwd, session)
	M.session_map[name] = session_data
	return session_data
end

function M.get_session_data(name)
	return M.session_map[name]
end

return M

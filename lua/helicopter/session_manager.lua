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
	new_session_data:on_update(function(json_response)
		new_session_data:handle_update(json_response)
	end)
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

---@param update_type UpdateType
---@param callback Callback
---@return number
function ManagedSession:on_update_type(update_type, callback)
	return self.session:on_session_update(update_type, callback)
end

---@param callback Callback
---@return table<UpdateType, number>
function ManagedSession:on_update(callback)
	local callback_ids = {}
	for _, update_type in pairs(Session.UpdateType) do
		local id = self:on_update_type(update_type, callback)
		callback_ids[update_type] = id
	end
	return callback_ids
end

---@param update_type UpdateType
---@param id number
function ManagedSession:del_update_callback(update_type, id)
	return self.session:del_update_callback(update_type, id)
end

---@param callback_ids table<UpdateType, number>
function ManagedSession:del_update_callbacks(callback_ids)
	for update_type, id in pairs(callback_ids) do
		self:del_update_callback(update_type, id)
	end
end

-- TODO:

---@class ResourceLink
---@field name string
---@field uri string

---@class Prompt
---@field text? string
---@field resource_link? ResourceLink

---@param prompts Prompt[]
---@param callback? Callback
---@return ManagedSession
function ManagedSession:prompt(prompts, callback)
	local content_blocks = {}
	for _, prompt in pairs(prompts) do
		local cb = {}
		if prompt.text then
			cb.type = "text"
			cb.text = prompt.text
		elseif prompt.resource_link then
			cb.type = "resource_link"
			cb.name = prompt.resource_link.name
			cb.uri = prompt.resource_link.uri
		else
			error("session_manager: unrecoginzed prompt type")
		end
		table.insert(content_blocks, cb)
	end
	self.session:prompt(content_blocks, callback)
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

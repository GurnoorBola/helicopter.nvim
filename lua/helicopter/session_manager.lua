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
---@field package session Session
---@field package update_callbacks UpdateInfo[]
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
		update_callbacks = {},
	}
	setmetatable(new_session_data, { __index = self })
	new_session_data.update_callbacks = new_session_data:on_update(function(json_response)
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

---@class UpdateInfo
---@field update_type UpdateType
---@field id number

---@param update_type UpdateType
---@param callback Callback
---@return UpdateInfo
function ManagedSession:on_update_type(update_type, callback)
	local id = self.session:on_session_update(update_type, callback)
	local update_info = { update_type = update_type, id = id }
	return update_info
end

---@param callback Callback
---@return UpdateInfo[]
function ManagedSession:on_update(callback)
	local update_info_list = {}
	for _, update_type in pairs(Session.UpdateType) do
		local update_info = self:on_update_type(update_type, callback)
		table.insert(update_info_list, update_info)
	end
	return update_info_list
end

---@param update_info UpdateInfo
function ManagedSession:del_update_callback(update_info)
	return self.session:del_update_callback(update_info.update_type, update_info.id)
end

---@param update_info_list UpdateInfo[]
function ManagedSession:del_update_callbacks(update_info_list)
	for _, update_info in ipairs(update_info_list) do
		self:del_update_callback(update_info)
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
			error("session_manager: cannot send prompt; unrecoginzed prompt type")
		end
		table.insert(content_blocks, cb)
	end
	self.session:prompt(content_blocks, callback)
	return self
end

local session_map = {}

---The session that the user is currently directly interacting with
---@type ManagedSession|nil
local active_session = nil

---Creates a new managed session
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
	session_map[name] = session_data
	return session_data
end

---@return ManagedSession|nil
function M.get_active_session()
	return active_session
end

---@param name string
function M.set_active_session(name)
	local managed_session = M.get_managed_session(name)
	active_session = managed_session
	return active_session
end

---@param name string
---@return ManagedSession
function M.get_managed_session(name)
	if not session_map[name] then
		error("session_manager: session " .. name .. " not found")
	end
	return session_map[name]
end

function M.del_managed_session(name)
	local managed_session = M.get_managed_session(name)
	managed_session:del_update_callbacks(managed_session.update_callbacks)
	session_map[name] = nil
end

return M

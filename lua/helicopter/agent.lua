-- ACP implementation
-- If we need the result we should define a callback with a json_result paramter
-- Otherwise fire and forget
--
-- Notifications can come in on response

local M = {}

local Json = require("helicopter.json")
local Config = require("helicopter.config")
local Utils = require("helicopter.utils")

local JSON_RPC_VERSION = "2.0"

--- Helpers ---

local curr_id = 0
---@param method string
---@param params JsonObject
---@param notification? boolean
---@return JsonObject
local function build_request(method, params, notification)
	curr_id = curr_id + 1
	local request = {
		jsonrpc = JSON_RPC_VERSION,
		method = method,
		params = params,
	}
	if not notification then
		request.id = curr_id
	end
	return request
end

local function parse_response(str_response)
	local json_response = Json.decode(str_response)
	if not json_response.error then
		return json_response
	end
	print("[Error] Code:", json_response.error.code, "Message:", json_response.error.message)
end

---@alias Callback fun(json_obj:JsonObject)

---@class EventHandler
---@field private _num_callbacks number
---@field private _callbacks table<number, Callback>
local EventHandler = {}

function EventHandler:new()
	local new_event_handler = {
		_num_callbacks = 0,
		_callbacks = {},
	}
	return setmetatable(new_event_handler, { __index = self })
end

---@param callback Callback
---@return number
function EventHandler:register(callback)
	self._num_callbacks = self._num_callbacks + 1
	self._callbacks[self._num_callbacks] = callback
	return self._num_callbacks
end

---@param id number
function EventHandler:unregister(id)
	if not self._callbacks[id] then
		error("event handler: callback unregister failed; " .. id .. " is not a registered callback")
	end
	self._callbacks[id] = nil
end

---@param json_obj JsonObject
function EventHandler:trigger(json_obj)
	for _, callback in pairs(self._callbacks) do
		callback(json_obj)
	end
end

--- Servers ---

---@alias JsonObject table<string, any>

---@class Server
---@field private _id number|nil
---@field private _cmd string[]
---@field private _callbacks table<number, Callback>
---@field private _sessions table<string, Session>
---@field private _last string
M.Server = {}

---@return Server
function M.Server:new(cmd)
	local new_server = {
		_cmd = cmd,
		_callbacks = {},
		_sessions = {},
		_last = "",
	}
	return setmetatable(new_server, { __index = self })
end

---@package
---@param json_request JsonObject
---@param callback? Callback
---@return number
function M.Server:_send_request(json_request, callback)
	if callback and json_request.id then
		self._callbacks[json_request.id] = callback
	end
	local str_request = Json.encode(json_request) .. "\n"
	return vim.fn.chansend(self._id, str_request)
end

---@package
---@param json_response JsonObject
---@return number
function M.Server:_send_response(json_response)
	local str_response = Json.encode(json_response) .. "\n"
	return vim.fn.chansend(self._id, str_response)
end

-- Last line may be incomplete if stream doesnt end in ''
-- Never returns a ''
---@private
---@param data string[]
---@return string[]
function M.Server:_get_lines(data)
	data[1] = self._last .. data[1]
	self._last = table.remove(data)
	return data
end

---@private
---@param str_received string
function M.Server:_on_receive(str_received)
	local json_received = parse_response(str_received)
	if not json_received then
		return
	end

	-- Notification
	if not json_received.id then
		local session = self._sessions[json_received.params.sessionId]
		session:_update(json_received.params.update)
		return
	end

	-- Request
	if json_received.method then
		local session = self._sessions[json_received.params.sessionId]
		session:_handle_request(json_received)
		return
	end

	-- Response
	if self._callbacks[json_received.id] then
		local callback = self._callbacks[json_received.id]
		self._callbacks[json_received.id] = nil
		callback(json_received.result)
	end
end

---@return number
function M.Server:start()
	self._id = vim.fn.jobstart(Config.agent_start_cmd, {
		on_stdout = function(_, data, _)
			local lines = self:_get_lines(data)
			for _, str_received in ipairs(lines) do
				self:_on_receive(str_received)
			end
		end,
		on_exit = function()
			print("Server shutdown!")
		end,
	})
	return self._id
end

function M.Server:stop()
	vim.fn.jobstop(self._id)
	self._id = nil
end

-- Initializes the agent and executes callback if all checks pass
---@param callback Callback
function M.Server:initialize(callback)
	local json_request = build_request("initialize", Config.initialize_request)
	self:_send_request(json_request, function(json_response)
		-- TODO: check response and configure client
		callback(json_response)
	end)
end

---@param method_id string
---@param callback Callback
function M.Server:authenticate(method_id, callback)
	local json_request = build_request("authenticate", { method_id = method_id })
	self:_send_request(json_request, function(json_response)
		-- TODO: map the method_id to the handler for that auth method
		-- execute appropriate authentication logic
		callback(json_response)
	end)
end

---@param params JsonObject
---@param callback? Callback
---@return Session
function M.Server:new_session(params, callback)
	---@type Session
	local session
	session = M.Session:new(self, params, function(json_response)
		self._sessions[session._id] = session
		if callback then
			callback(json_response)
		end
	end)
	return session
end

---@param session Session
---@param callback? Callback
function M.Server:delete_session(session, callback)
	return session:_delete(function(json_response)
		if callback then
			callback(json_response)
		end
		self._sessions[session._id] = nil
		session._server = nil
	end)
end

--- Sessions ---

--- An ACP Session
---@class Session
---@field package _server Server
---@field package _id string
---@field private _event_handlers table<UpdateType, EventHandler>
---@field private _queue Queue
---@field private _request_handlers table<string, function>
M.Session = {}

---@param server Server
---@param params JsonObject
---@param callback? Callback
---@return Session
function M.Session:new(server, params, callback)
	local new_session = {
		_server = server,
		_id = "unset",
		-- Handlers for when session recieves a notification or request
		_event_handlers = {},
		_queue = Utils.queue:new(),
	}

	setmetatable(new_session, { __index = self })

	new_session._queue:push("~")

	local json_request = build_request("session/new", params)

	server:_send_request(json_request, function(json_response)
		-- TODO: setup the session object
		new_session._queue:pop()

		new_session._id = json_response.sessionId
		if callback then
			callback(json_response)
		end

		if not new_session._queue:empty() then
			local next = new_session._queue:peek()
			next()
		end
	end)

	return new_session
end

---@param content_blocks JsonObject[]
---@param callback? Callback
---@return self
function M.Session:prompt(content_blocks, callback)
	local prompt_cmd = function()
		local json_request = build_request("session/prompt", { sessionId = self._id, prompt = content_blocks })
		self._server:_send_request(json_request, function(json_response)
			self._queue:pop()

			if callback then
				callback(json_response)
			end

			if not self._queue:empty() then
				local next = self._queue:peek()
				next()
			end
		end)
	end
	self._queue:push(prompt_cmd)
	if self._queue:size() == 1 then
		prompt_cmd()
	end
	return self
end

---@enum UpdateType
M.Session.UpdateType = {
	user_message_chunk = "user_message_chunk",
	agent_message_chunk = "agent_message_chunk",
	agent_thought_chunk = "agent_thought_chunk",
	tool_call = "tool_call",
	tool_call_update = "tool_call_update",
	plan = "plan",
	available_commands_update = "available_commands_update",
	current_mode_update = "current_mode_update",
	config_option_update = "config_option_update",
	session_info_update = "session_info_update",
	usage_update = "usage_update",
}

---@param type UpdateType
---@param callback Callback
---@return number
function M.Session:on_session_update(type, callback)
	if not self._event_handlers[type] then
		self._event_handlers[type] = EventHandler:new()
	end
	local event_handler = self._event_handlers[type]
	return event_handler:register(callback)
end

---@param type UpdateType
---@param id number
function M.Session:del_update_callback(type, id)
	if not self._event_handlers[type] then
		error("session: delete callback failed; no handler for update type " .. type)
	end
	local event_handler = self._event_handlers[type]
	event_handler:unregister(id)
end

---@package
---@param update JsonObject
function M.Session:_update(update)
	-- TODO: switch on update type and call appropriate handler
	local event_handler = self._event_handlers[update.sessionUpdate]
	if event_handler then
		event_handler:trigger(update)
	end
end

---@return self
function M.Session:cancel()
	local json_request = build_request("session/cancel", { sessionId = self._id }, true)
	self._server:_send_request(json_request)
	return self
end

---Sessions should be deleted through the server so they are deregistered correctly
---@package
---@param callback? Callback
function M.Session:_delete(callback)
	local delete_cmd = function()
		local json_request = build_request("session/delete", { sessionId = self._id })
		self._server:_send_request(json_request, function(json_response)
			self._queue:clear()
			-- TODO: do other cleanup activities
			if callback then
				callback(json_response)
			end
		end)
	end
	self._queue:push(delete_cmd)
	if self._queue:size() == 1 then
		delete_cmd()
	end
end

--- Session Requests ---

-- Defines callback behavior upon handling a request of type method
---@param method string
---@param callback Callback
---@return number
function M.Session:on_session_request(method, callback)
	if not self._event_handlers[method] then
		self._event_handlers[method] = EventHandler:new()
	end
	local event_handler = self._event_handlers[method]
	return event_handler:register(callback)
end

---@param method string
---@param id number
function M.Session:del_request_callback(method, id)
	if not self._event_handlers[method] then
		error("session: delete callback failed; no handler for request type " .. method)
	end
	local event_handler = self._event_handlers[method]
	event_handler:unregister(id)
end

---@package
---@param json_request JsonObject
function M.Session:_handle_request(json_request)
	local method = json_request.method

	local handler = self._request_handlers[method]
	-- WARN: will be removed once all handlers implemented
	if not handler then
		handler = function(_, _)
			print("no handler for ", method)
		end
	end
	handler(self, json_request.params)

	if self._event_handlers[method] then
		local even_handler = self._event_handlers[method]
		even_handler:trigger(json_request)
	end
end

M.Session._request_handlers = {
	["fs/read_text_file"] = M.Session._read_text_file,
	["fs/write_text_file"] = M.Session._write_text_file,
}

---@private
function M.Session:_read_text_file(params)
	-- TODO: handle reading a text file
	print("read text unimplemented... oops now we are stuck")
end

---@private
function M.Session:_write_text_file(params)
	-- TODO: handle writing a text file
	print("write text unimplemented... oops now we are stuck")
end

return M

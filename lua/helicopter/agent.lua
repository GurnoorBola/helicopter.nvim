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

--- Servers ---

---@alias JsonObject table<string, any>
---@alias Callback fun(json_obj:JsonObject)

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

---@package
---@param session Session
function M.Server:_register_session(session)
	self._sessions[session._id] = session
end

---@package
---@param session Session
function M.Server:_unregister_session(session)
	self._sessions[session._id] = nil
end

---@param params JsonObject
---@param callback Callback
---@return Session
function M.Server:new_session(params, callback)
	return M.Session:new(self, params, callback)
end

--- Sessions ---

--- An ACP Session
---@class Session
---@field package _server Server
---@field package _id string
---@field private _callbacks Callback[]
---@field private _queue Queue
---@field private _request_handlers table<string, function>
M.Session = {}

---@param server Server
---@param params JsonObject
---@param callback Callback
---@return Session
function M.Session:new(server, params, callback)
	local new_session = {
		_server = server,
		_id = "unset",
		-- Callbacks for when session recieves a message (notification or request)
		_callbacks = {},
		_queue = Utils.queue:new(),
	}

	setmetatable(new_session, { __index = self })

	new_session._queue:push("~")

	local json_request = build_request("session/new", params)

	server:_send_request(json_request, function(json_response)
		-- TODO: setup the session object
		new_session._queue:pop()

		new_session._id = json_response.sessionId
		server:_register_session(new_session)
		callback(json_response)

		if not new_session._queue:empty() then
			local next = new_session._queue:peek()
			next()
		end
	end)

	return new_session
end

---@param prompt JsonObject
---@param callback Callback
---@return self
function M.Session:prompt(prompt, callback)
	local prompt_cmd = function()
		local json_request = build_request("session/prompt", { sessionId = self._id, prompt = prompt })
		self._server:_send_request(json_request, function(json_response)
			self._queue:pop()

			callback(json_response)

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

---@param type string
---@param callback Callback
---@return self
function M.Session:on_session_update(type, callback)
	self._callbacks[type] = callback
	return self
end

---@package
---@param update JsonObject
function M.Session:_update(update)
	-- TODO: switch on update type and call appropriate handler
	local callback = self._callbacks[update.sessionUpdate]
	if callback then
		callback(update)
	end
end

---@return self
function M.Session:cancel()
	local json_request = build_request("session/cancel", { sessionId = self._id }, true)
	self._server:_send_request(json_request)
	return self
end

---@param callback Callback
function M.Session:delete(callback)
	local delete_cmd = function()
		local json_request = build_request("session/delete", { sessionId = self._id })
		self._server:_send_request(json_request, function(json_response)
			self._queue:clear()
			self._server:_unregister_session(self)
			-- TODO: do other cleanup activities
			callback(json_response)
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
---@return self
function M.Session:on_session_request(method, callback)
	self._callbacks[method] = callback
	return self
end

---@package
---@param json_request JsonObject
function M.Session:_handle_request(json_request)
	local method = json_request.method

	local handler = self._request_handlers[method]
	handler(self, json_request.params)

	if self._callbacks[method] then
		local callback = self._callbacks[method]
		callback(json_request)
	end
end

M.Session._request_handlers = {
	["fs/read_text_file"] = M.Session._read_text_file,
	["fs/write_text_file"] = M.Session._write_text_file,
}

---@private
function M.Session:_read_text_file(params)
	-- TODO: handle reading a text file
end

---@private
function M.Session:_write_text_file(params)
	-- TODO: handle writing a text file
end

return M

-- ACP implementation
-- If we need the result we should define a callback with a json_result paramter
-- Otherwise fire and forget
--
-- Notifications can come in on response

local M = {}

local json = require("helicopter.json")
local config = require("helicopter.config")
local utils = require("helicopter.utils")

local MAX_REQUESTS = 1000
local JSON_RPC_VERSION = "2.0"

local callbacks = {}

-- Maps session id to session object
local active_sesssions = {}

local curr_id = 0
local function build_request(method, params)
	curr_id = (curr_id + 1) % MAX_REQUESTS
	return {
		jsonrpc = JSON_RPC_VERSION,
		id = 0,
		method = method,
		params = params,
	}
end

local function parse_response(str_response)
	local json_response = json.decode(str_response)
	if not json_response.error then
		return json_response
	end
	print("[Error] Code:", json_response.error.code, "Message:", json_response.error.message)
end

local function register_callback(request_id, on_response)
	callbacks[request_id] = on_response
end

local function send_request(json_request, on_response)
	if on_response then
		register_callback(json_request.id, on_response)
	end
	local str_request = json.encode(json_request) .. "\n"
	return vim.fn.chansend(M.id, str_request)
end

-- Last line may be incomplete if stream doesnt end in ''
-- Never returns a ''
local last = ""
local function get_lines(data)
	data[1] = last .. data[1]
	last = table.remove(data)
	return data
end

local function on_response(str_response)
	local json_response = parse_response(str_response)
	if not json_response then
		return
	end

	if not json_response.id then
		local session = active_sesssions[json_response.params.sessionId]
		-- NOTE: end users don't call update but can define what happens
		-- on certain update types using on_update_<type>
		session:_update(json_response.params.update)
		return
	end

	if callbacks[json_response.id] then
		local callback = callbacks[json_response.id]
		callbacks[json_response.id] = nil
		callback(json_response.result)
	end
end

local function on_stdout(_, data, _)
	local lines = get_lines(data)
	for _, str_response in ipairs(lines) do
		on_response(str_response)
	end
end

function M.start_server()
	M.id = vim.fn.jobstart(config.agent_start_cmd, {
		on_stdout = on_stdout,
		on_exit = function()
			print("Server shutdown!")
		end,
	})
end

function M.stop_server()
	vim.fn.jobstop(M.id)
	M.id = nil
end

-- Initializes the agent and executes callback if all checks pass
function M.initialize(callback)
	local json_request = build_request("initialize", config.initialize_request)
	send_request(json_request, function(json_response)
		-- TODO: check response and configure client
		callback(json_response)
	end)
end

function M.authenticate(method_id, callback)
	local json_request = build_request("authenticate", { method_id = method_id })
	send_request(json_request, function(json_response)
		-- TODO: map the method_id to the handler for that auth method
		-- execute appropriate authentication logic
		callback(json_response)
	end)
end

-- Session object that is produced from the new function
--
-- Using functions from the Session.seq table will
-- implement sequential semantics on the session object

-- To be a sequential command means that any command that was executed before
-- it must finish its callback before running this command
--
-- If a sequential command queue is empty place a sentinel and execute command
-- If a sequential command queue is not empty place command on queue
--
-- then it should run callback
-- then it should pop top and run next command
--
--
M.Session = {}
M.Session.seq = {}

function M.Session:new(params, callback)
	local new_session = {
		_updates = {},
		_callbacks = {},

		seq = {
			_queue = utils.queue:new(),
		},
	}
	new_session.seq.session = new_session

	setmetatable(new_session, { __index = self })
	setmetatable(new_session.seq, { __index = self.seq })

	local json_request = build_request("session/new", params)

	send_request(json_request, function(json_response)
		-- TODO: setup the session object
		new_session.id = json_response.sessionId
		active_sesssions[new_session.id] = new_session
		callback(json_response)
	end)
	return new_session
end

-- Returns a session.seq
-- Creates a dummy marker to show an in progress session being initialized
-- session object can still be operated on and will work as expected
function M.Session.seq:new(params, callback)
	local new_session = {
		_updates = {},
		_callbacks = {},

		seq = {
			_queue = utils.queue:new(),
		},
	}
	new_session.seq.session = new_session

	setmetatable(new_session, { __index = self })
	setmetatable(new_session.seq, { __index = self.seq })

	new_session.seq._queue:push("~")

	local json_request = build_request("session/new", params)

	send_request(json_request, function(json_response)
		new_session.seq._queue:pop()

		new_session.id = json_response.sessionId
		active_sesssions[new_session.id] = new_session
		callback(json_response)

		if new_session.seq._queue:size() ~= 0 then
			local next = new_session.seq._queue:peek()
			next()
		end
	end)

	return new_session.seq
end

function M.Session:prompt(prompt, callback)
	local json_request = build_request("session/prompt", { sessionId = self.id, prompt = prompt })
	send_request(json_request, function(json_response)
		callback(json_response)
	end)
end

function M.Session.seq:prompt(prompt, callback)
	local session = self.session
	local cmd = function()
		session:prompt(prompt, function(json_response)
			self._queue:pop()
			callback(json_response)
			if self._queue:size() ~= 0 then
				local next = self._queue:peek()
				next()
			end
		end)
	end
	self._queue:push(cmd)
	if self._queue:empty() then
		cmd()
	end
	return self
end

function M.Session:on_session_update(type, callback)
	self._callbacks[type] = callback
end

function M.Session:_update(update)
	table.insert(self._updates, update)
	-- TODO: switch on update type and call appropriate handler
	local callback = self._callbacks[update.sessionUpdate]
	callback(update)
end

return M

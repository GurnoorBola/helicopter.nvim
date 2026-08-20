-- ACP implementation

local M = {}

local json = require("helicopter.json")
local config = require("helicopter.config")

local MAX_REQUESTS = 1000
local JSON_RPC_VERSION = "2.0"

local responses = {}
local callbacks = {}

local curr_id = 0
local function build_request(method, params)
	curr_id = (curr_id + 1) % MAX_REQUESTS
	return {
		jsonrpc = JSON_RPC_VERSION,
		id = curr_id,
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

local function await(request_id, on_response)
	callbacks[request_id] = on_response
end

local function send_request(json_request, on_response)
	if on_response then
		await(json_request.id, on_response)
	end
	local str_request = json.encode(json_request) .. "\n"
	return vim.fn.chansend(M.id, str_request)
end

function M.read_response(request_id)
	local json_response = responses[request_id]
	responses[request_id] = nil
	return json_response
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
	if json_response then
		responses[json_response.id] = json_response
		if callbacks[json_response.id] then
			local callback = callbacks[json_response.id]
			callbacks[json_response.id] = nil
			callback()
		end
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

-- Sends a request
function M.initialize(callback)
	local json_request = build_request("initialize", config.initialize_request)
	send_request(json_request, function()
		-- TODO: check response and configure client
		callback(json_request.id)
	end)
end

function M.authenticate(method_id) end

return M

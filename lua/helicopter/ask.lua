local M = {}

local Utils = require("helicopter.utils")
local Servers = require("helicopter.servers")

-- TODO: update this to build better prompts
local function build_prompt(query, lines)
	local prompt = "Question: " .. query .. "\nContext for question:" .. Utils.flatten_str_arr(lines)
	return prompt
end

local function do_select_and_ask(session, opts)
	local lines = Utils.get_lines(opts.line1, opts.line2)
	local query = Utils.prompt_input()
	local text = build_prompt(query, lines)
	local prompt = { { type = "text", text = text } }

	local response = ""
	session:on_session_update("agent_message_chunk", function(json_response)
		if json_response then
			response = response .. json_response.content.text
		end
	end)
	session:prompt(prompt, function()
		print("Received:", response)
	end)
end

-- TODO:
-- Request should show as a ... signal when agent working and green check when done
-- Can view its output by toggling a floating window for output to show
-- in progress agent thought or final output
-- can continue chatting in that window with same context
-- floating window can continue the chat within that session with same context
--
local curr_session
function M.select_and_ask_curr(opts)
	if curr_session == nil then
		return M.select_and_ask_new(opts)
	end
	do_select_and_ask(curr_session, opts)
end

function M.select_and_ask_new(opts)
	local server = Servers.get_server()

	curr_session = server:new_session({
		cwd = os.getenv("PWD") or io.popen("cd"):read(),
		mcpServers = {},
	}, function(json_response)
		print("started session:", json_response.sessionId)
	end)

	return do_select_and_ask(curr_session, opts)
end

return M

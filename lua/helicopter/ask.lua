local M = {}

local Utils = require("helicopter.utils")
local Json = require("helicopter.json")
local Servers = require("helicopter.servers")
local SessionManager = require("helicopter.session_manager")
local Ui = require("helicopter.ui")

-- TODO: update this to build better prompts
local function build_question_prompt(query, lines)
	local json_prompt = {}
	json_prompt["Question"] = query
	json_prompt["Context for question"] = lines
	local str_prompt = Json.encode(json_prompt)
	return str_prompt
end

---@param managed_session ManagedSession
---@param opts table
local function do_select_and_ask(managed_session, opts)
	local lines = Utils.get_lines(opts.line1, opts.line2)
	local query = Utils.prompt_input()
	local text = build_question_prompt(query, lines)
	local prompt = { { type = "text", text = text } }

	local response = ""

	-- WARN: temporary will be replaced by simply passing the managed_session to Ui open_chat
	-- open chat will hook into managed session and adds special behavior on update such as showing the new chats
	managed_session:on_update("agent_message_chunk", function(update)
		response = response .. update.content.text
	end)

	managed_session:prompt(prompt, function()
		print("Received:", response)
	end)
end

local curr_session
function M.select_and_ask_curr(opts)
	if curr_session == nil then
		return M.select_and_ask_new(opts)
	end
	do_select_and_ask(curr_session, opts)
end

local id = 1
function M.select_and_ask_new(opts)
	local session_name = "ask_sess#" .. id
	id = id + 1

	curr_session = SessionManager.new_session(session_name, os.getenv("PWD") or io.popen("cd"):read(), function()
		Ui.notify("new session: " .. session_name, "HelicopterStandard")
	end)

	return do_select_and_ask(curr_session, opts)
end

return M

local M = {}

local Utils = require("helicopter.utils")
local Json = require("helicopter.json")
local SessionManager = require("helicopter.session_manager")
local Ui = require("helicopter.ui")

-- TODO: update this to build better prompts
local function build_context(opts)
	local lines = Utils.get_lines(opts.line1, opts.line2)
	local flattened_lines = Utils.flatten_str_arr(lines)
	local json_prompt = {}
	json_prompt["filename"] = vim.api.nvim_buf_get_name(0)
	json_prompt["line_range"] = opts.line1 .. "-" .. opts.line2
	json_prompt["context"] = flattened_lines
	local str_prompt = Json.encode(json_prompt)
	return str_prompt
end

local id = 1
function M.ask(opts)
	local active_session = SessionManager.get_active_session()
	if active_session and Ui.is_chat_open(active_session) then
		Ui.chat_hide()
		return
	end

	if active_session == nil or (#opts.fargs == 1 and opts.fargs[1] == "new") then
		local session_name = "ask_sess#" .. id
		id = id + 1

		SessionManager.new_session(session_name, os.getenv("PWD") or io.popen("cd"):read(), function()
			Ui.notify("new session: " .. session_name, "HelicopterStandard")
		end)

		active_session = SessionManager.set_active_session(session_name)
	end

	local context
	if opts.range == 2 then
		context = build_context(opts)
	end

	Ui.chat_open(active_session)

	if opts.range == 2 then
		Ui.chat_append_input_text({ context })
	end
end

return M

local M = {}

local Utils = require("helicopter.utils")
local Servers = require("helicopter.servers")
local NuiText = require("nui.text")

-- TODO: update this to build better prompts
local function build_prompt(query, lines)
	local prompt = "Query: " .. query .. "\nContext:" .. Utils.flatten_str_arr(lines)
	return prompt
end

-- TODO: show text popup on command start that fills up with agent response
-- INFO DUMP:
-- Request should show as a ... signal when agent working,
-- yellow checkmark when done but not viewed, and green check when viewed
-- getting a green check updates last used session
-- green check mark can then be resolved if we are done or we can ask follow up
-- follow up will automatically send to last used session
-- command for explicit new session
-- command for pulling up session list and sending follow up with exisiting session
local curr_session
function M.select_and_ask(opts)
	local server = Servers.get_server()

	local lines = Utils.get_lines(opts.line1, opts.line2)
	local query = Utils.prompt_input()
	local text = build_prompt(query, lines)
	local prompt = { { type = "text", text = text } }

	if curr_session == nil then
		curr_session = server:new_session({
			cwd = "/home/noor/Projects/neovim_plugins/helicopter.nvim/",
			mcpServers = {},
		}, function(json_response)
			print("started session:", json_response.sessionId)
		end)
	end
	local session = curr_session

	local response = ""
	session:on_session_update("agent_message_chunk", function(json_response)
		if json_response then
			response = response .. json_response.content.text
		end
	end)
	session:prompt(prompt, function()
		print("Received:", response)
	end)
	-- session:delete(function()
	-- 	print("Deleted session:", id)
	-- end)
end

return M

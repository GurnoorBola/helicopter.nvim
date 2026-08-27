local M = {}

local Utils = require("helicopter.utils")
local Servers = require("helicopter.servers")
local Json = require("helicopter.json")

-- TODO: update this to build better prompts
local function build_prompt(query, lines)
	local prompt = "Query: " .. query .. "\n Context:" .. Utils.flatten_str_arr(lines)
	return prompt
end

function M.select_and_ask(opts)
	local server = Servers.get_server()

	local lines = Utils.get_lines(opts.line1, opts.line2)
	local query = Utils.prompt_input()
	local prompt = build_prompt(query, lines)

	local id = nil
	local session = server:new_session({
		cwd = "/home/noor/Projects/neovim_plugins/helicopter.nvim/",
		mcpServers = {},
	}, function(json_response)
		id = json_response.sessionId
		print("started session:", id)
	end)
	session:on_session_update("agent_message_chunk", function(json_response)
		print("Response:", Json.encode(json_response))
	end)
	session:prompt(prompt, function()
		print("Sent:", prompt)
	end)
	session:delete(function()
		print("Deleted session:", id)
	end)
end

return M

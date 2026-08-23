local M = {}

local utils = require("helicopter.utils")
local agent = require("helicopter.agent")

-- TODO: update this to build better prompts
local function build_prompt(query, lines)
	local prompt = "Query: " .. query .. "\n Context:" .. utils.flatten_str_arr(lines)
	return prompt
end

function M.select_and_ask(opts)
	local lines = utils.get_lines(opts.line1, opts.line2)
	local query = utils.prompt_input()
	local prompt = build_prompt(query, lines)

	-- local seq_session = agent.Session.seq:new()
	-- seq_session:prompt()

	local response = agent.send_message(prompt)
	print(response)
end

return M

local M = {}

local Utils = require("helicopter.utils")
local Agent = require("helicopter.agent")

-- TODO: update this to build better prompts
local function build_prompt(query, lines)
	local prompt = "Query: " .. query .. "\n Context:" .. Utils.flatten_str_arr(lines)
	return prompt
end

function M.select_and_ask(opts)
	local lines = Utils.get_lines(opts.line1, opts.line2)
	local query = Utils.prompt_input()
	local prompt = build_prompt(query, lines)

	local response = agent.send_message(prompt)
	print(response)
end

return M

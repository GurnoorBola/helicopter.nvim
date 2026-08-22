-- Select a part of the codebase and ask a question about it
-- Should store the selected text and open a prompt for the user's query
-- Should store in a table
local M = {}

local config = require("helicopter.config")
local agent = require("helicopter.agent")
local json = require("helicopter.json")

M.ask = require("helicopter.ask")

function M.setup(opts)
	opts = opts or {}
	config = setmetatable(opts, { __index = config })
	agent.start_server()

	agent.initialize(function(json_response)
		if json_response then
			print("Response Received:", json.encode(json_response))
		else
			print("Failed to initalize. Stopping server...")
			agent.stop_server()
		end
	end)
end

-- print("Helicopter nvim loaded!")
return M

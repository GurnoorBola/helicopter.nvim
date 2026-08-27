-- Select a part of the codebase and ask a question about it
-- Should store the selected text and open a prompt for the user's query
-- Should store in a table
local M = {}

local Config = require("helicopter.config")
local Servers = require("helicopter.servers")
local Json = require("helicopter.json")

M.ask = require("helicopter.ask")

function M.setup(opts)
	opts = opts or {}
	Config = setmetatable(opts, { __index = Config })
	local server = Servers.start_server(Config.agent_start_cmd)

	server:initialize(function(json_response)
		if json_response then
			print("Response Received:", Json.encode(json_response))
		else
			print("Failed to initalize. Stopping server...")
			server:stop()
		end
	end)
end

-- print("Helicopter nvim loaded!")
return M

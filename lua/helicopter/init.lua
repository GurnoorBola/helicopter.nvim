-- Select a part of the codebase and ask a question about it
-- Should store the selected text and open a prompt for the user's query
-- Should store in a table
local M = {}

local Config = require("helicopter.config")
local Servers = require("helicopter.servers")
local Ui = require("helicopter.ui")

M.ask = require("helicopter.ask")

function M.setup(opts)
	opts = opts or {}
	Config = setmetatable(opts, { __index = Config })
	local server = Servers.start_server(Config.agent_start_cmd)

	Ui.notify("Initializing agent...", "HelicopterInfo")
	server:initialize(function(json_response)
		if json_response then
			Ui.notify("Agent initialized!", "HelicopterSuccess")
		else
			Ui.notify("Failed to initalize. Stopping server...", "HelicopterError")
			server:stop()
		end
	end)
end

return M

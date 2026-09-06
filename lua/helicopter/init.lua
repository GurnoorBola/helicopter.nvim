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

	local client_title = Config.initialize_request.clientInfo.title
	local client_version = Config.initialize_request.clientInfo.version
	Ui.notify({
		{ str = "(" .. client_version .. ") ", status = "HelicopterMuted" },
		{ str = client_title, status = "HelicopterInfo" },
	})

	Ui.notify({
		{ str = " Initializing agent", status = "HelicopterHint" },
		{ str = "...", status = "HelicopterMuted" },
	})
	server:initialize(function(json_response)
		if json_response then
			Ui.notify(" Agent initialized!", "HelicopterSuccess")
			if json_response.agentInfo then
				local agent_title = json_response.agentInfo.title or json_response.agentInfo.name
				local agent_version = json_response.agentInfo.version
				Ui.notify({
					{ str = "(" .. agent_version .. ") ", status = "HelicopterMuted" },
					{ str = agent_title, status = "HelicopterInfo" },
				})
			end
		else
			Ui.notify("Failed to initalize. Stopping server...", "HelicopterError")
			server:stop()
		end
	end)
end

return M

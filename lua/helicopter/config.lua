local M = {}

-- The default configuration for Helicopter
-- use opts to override

M.agent_start_cmd = { "opencode", "acp" }

M.initialize_request = {
	protocolVersion = 1,
	clientCapabilities = {
		fs = {
			readTextFile = true,
			writeTextFile = true,
		},
		terminal = true,
	},
	clientInfo = {
		name = "helicopter-nvim",
		title = "Helicopter.nvim",
		version = "1.0.0",
	},
}

return M

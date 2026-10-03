local Helicopter = require("helicopter")

-- Ask a question in chat
vim.api.nvim_create_user_command("Ask", Helicopter.ask.ask, { nargs = "?", range = true })
--
-- vim.api.nvim_create_user_command("AgentHealth", agent.check_health, {})

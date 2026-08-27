local Helicopter = require("helicopter")

-- Query Selected Text
vim.api.nvim_create_user_command("AskSelected", Helicopter.ask.select_and_ask, { range = "%" })
--
-- vim.api.nvim_create_user_command("AgentHealth", agent.check_health, {})

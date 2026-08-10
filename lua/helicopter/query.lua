local M = {}

local utils = require("helicopter.utils")

function M.query_selected(start_ln, end_ln)
	local arr = utils.get_text(start_ln, end_ln)
	local prompt = utils.prompt_input()
end

return M

-- Select a part of the codebase and ask a question about it
-- Should store the selected text and open a prompt for the user's query
-- Should store in a table
local M = {}

local query = require("helicopter.query")

M.query = query

-- print("Helicopter nvim loaded!")
return M

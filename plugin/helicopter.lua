local helicopter = require("helicopter")

-- Query Selected Text
vim.api.nvim_create_user_command("QuerySelected", function(opts)
	helicopter.query.query_selected(opts.line1, opts.line2)
end, { range = true })

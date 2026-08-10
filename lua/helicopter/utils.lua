local M = {}

function M.print_arr(arr)
	for _, v in ipairs(arr) do
		print(v .. "\n")
	end
end

function M.get_text(start_ln, end_ln)
	if start_ln > end_ln then
		start_ln, end_ln = end_ln, start_ln
	end

	return vim.api.nvim_buf_get_lines(0, start_ln - 1, end_ln, true)
end

function M.prompt_input()
	return vim.fn.input("Enter query: ")
end

return M

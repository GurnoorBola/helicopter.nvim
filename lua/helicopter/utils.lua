local M = {}

function M.flatten_str_arr(arr)
	local res = ""
	for _, line in ipairs(arr) do
		res = res .. line .. "\n"
	end
	return res
end

function M.print_arr(arr)
	for _, v in ipairs(arr) do
		print(v .. "\n")
	end
end

function M.get_lines(start_ln, end_ln)
	if start_ln > end_ln then
		start_ln, end_ln = end_ln, start_ln
	end

	return vim.api.nvim_buf_get_lines(0, start_ln - 1, end_ln, true)
end

-- TODO: change this to display a floating box for input
function M.prompt_input()
	return vim.fn.input("> ")
end

return M

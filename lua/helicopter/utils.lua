local M = {}

M.queue = {}

function M.queue:new()
	local new_queue = {
		_front = 0,
		_back = 0,
		_data = {},
	}
	return setmetatable(new_queue, { __index = self })
end

function M.queue:push(val)
	self._front = self._front + 1
	self._data[self._front] = val
end

function M.queue:pop()
	local val = self._data[self._back]
	self._data[self._back] = nil
	self._back = self._back + 1
	return val
end

function M.queue:peek()
	return self._data[self._back]
end

function M.queue:size()
	return self._front - self._back
end

function M.queue:empty()
	return self:size() == 0
end

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

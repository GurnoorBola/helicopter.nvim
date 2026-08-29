local M = {}

---@class Queue
---@field private _front number
---@field private _back number
---@field private _data any[]
M.queue = {}

---@return Queue
function M.queue:new()
	local new_queue = {
		_front = 0,
		_back = 0,
		_data = {},
	}
	return setmetatable(new_queue, { __index = self })
end

---@return number
function M.queue:size()
	return self._back - self._front
end

---@return boolean
function M.queue:empty()
	return self:size() == 0
end

---@return self
function M.queue:clear()
	self._front = 0
	self._back = 0
	self._data = {}
	return self
end

---@param val any
function M.queue:push(val)
	self._data[self._back] = val
	self._back = self._back + 1
end

---@return any
function M.queue:peek()
	if not self:empty() then
		return self._data[self._front]
	end
end

---@return any
function M.queue:pop()
	if not self:empty() then
		local val = self:peek()
		self._data[self._front] = nil
		self._front = self._front + 1
		return val
	end
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

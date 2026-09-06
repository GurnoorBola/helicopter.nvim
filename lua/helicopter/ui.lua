local M = {}

local Config = require("helicopter.config")
local Utils = require("helicopter.utils")
local Popup = require("nui.popup")
local NuiLine = require("nui.line")

local ns_id = vim.api.nvim_create_namespace("helicopter")

-- highlights

---@enum Highlight
local Highlight = {
	Standard = "HelicopterStandard",
	Error = "HelicopterError",
	Warning = "HelicopterWarning",
	Success = "HelicopterSuccess",
	Hint = "HelicopterHint",
	Info = "HelicopterInfo",
	Muted = "HelicopterMuted",
}

vim.api.nvim_set_hl(0, Highlight.Standard, { link = "Normal", default = true })
vim.api.nvim_set_hl(0, Highlight.Error, { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, Highlight.Warning, { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, Highlight.Success, { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, Highlight.Hint, { link = "DiagnosticHint", default = true })
vim.api.nvim_set_hl(0, Highlight.Info, { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, Highlight.Muted, { link = "Comment", default = true })

-- notifications are stored for config.notification_len seconds
local notifications = Utils.queue:new()

local hidden = false
local notification_popup = Popup({
	position = {
		row = 0,
		col = vim.o.columns,
	},
	size = {
		width = 1,
		height = 1,
	},
	anchor = "NE",
	enter = false,
	focusable = false,
	relative = "win",
	buf_options = {
		modifiable = false,
	},
	win_options = {
		winblend = 10,
		winhighlight = "Normal:Normal",
	},
})

local function update_noti_popup()
	if hidden then
		return
	end
	if notifications:empty() then
		notification_popup:unmount()
		return
	end
	notification_popup:mount()

	---@type NuiLine[]
	local data = notifications:data()

	local max_width = 1
	for _, line in ipairs(data) do
		local length = line:content():len()
		max_width = length > max_width and length or max_width
	end

	vim.bo[notification_popup.bufnr].modifiable = true
	notification_popup:update_layout({
		position = {
			row = 0,
			col = vim.o.columns,
		},
		size = {
			width = max_width,
			height = notifications:size(),
		},
	})
	for i, line in ipairs(data) do
		line:render(notification_popup.bufnr, ns_id, i)
	end
	vim.api.nvim_buf_call(notification_popup.bufnr, function()
		vim.cmd("%right " .. max_width)
	end)
	vim.bo[notification_popup.bufnr].modifiable = false
end

-- keep notifications anchored to top left
vim.api.nvim_create_autocmd("VimResized", {
	callback = function()
		update_noti_popup()
	end,
})

---@class HelicopterText
---@field str string
---@field status Highlight

-- push a notification to the queue and update notification element
---@overload fun(texts:HelicopterText[])
---@param str string
---@param status? Highlight
function M.notify(str, status)
	local msg = NuiLine()
	if type(str) == "table" then
		for _, text in ipairs(str) do
			msg:append(text.str, text.status)
		end
	else
		msg:append(str, status)
	end
	-- TODO: change this to switch on status and make notifications nicer
	notifications:push(msg)

	update_noti_popup()

	vim.defer_fn(function()
		notifications:pop()
		update_noti_popup()
	end, Config.notification_len * 1000)
end

function M.hide_notifications()
	hidden = true
	notification_popup:unmount()
end

return M

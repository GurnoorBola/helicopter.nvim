local M = {}

local Config = require("helicopter.config")
local Utils = require("helicopter.utils")
local Popup = require("nui.popup")

-- notifications are stored for config.notification_len seconds
local notifications = Utils.queue:new()

local hidden = false
local NOTI_WIDTH = 20
local notification_popup = Popup({
	position = {
		row = vim.o.lines - vim.o.cmdheight - 2,
		col = 0,
	},
	size = {
		width = NOTI_WIDTH,
		height = 1,
	},
	anchor = "SW",
	enter = false,
	focusable = false,
	relative = "win",
	buf_options = {
		modifiable = true,
		readonly = false,
	},
	win_options = {
		winblend = 10,
		winhighlight = "Normal:Keyword",
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
	notification_popup:update_layout({
		size = {
			width = NOTI_WIDTH,
			height = notifications:size(),
		},
	})
	vim.api.nvim_buf_set_lines(notification_popup.bufnr, 0, -1, false, notifications:data())
end

-- push a notification to the queue and update notification element
---@param msg string
function M.notify(msg)
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

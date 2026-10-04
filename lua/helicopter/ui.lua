local M = {}

local Config = require("helicopter.config")
local Utils = require("helicopter.utils")
local SessionManager = require("helicopter.session_manager")
local Popup = require("nui.popup")
local NuiLine = require("nui.line")
local Layout = require("nui.layout")

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
	Highlight = "HelicopterHighlight",
}

vim.api.nvim_set_hl(0, Highlight.Standard, { link = "Normal", default = true })
vim.api.nvim_set_hl(0, Highlight.Error, { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, Highlight.Warning, { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, Highlight.Success, { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, Highlight.Hint, { link = "DiagnosticHint", default = true })
vim.api.nvim_set_hl(0, Highlight.Info, { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, Highlight.Muted, { link = "Comment", default = true })
vim.api.nvim_set_hl(0, Highlight.Highlight, { link = "CursorLine", default = true })

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

-- TODO:
-- prompt window floating

local chat_history = Popup({
	enter = false,
	focusable = true,
	border = {
		style = "double",
		text = {
			top = "Session",
			top_align = "center",
		},
	},
})

local chat_input = Popup({
	enter = true,
	focusable = true,
	border = "double",
})

local chat_config = {
	options = {
		position = "50%",
		size = {
			width = "80%",
			height = "80%",
		},
	},
	box = Layout.Box({
		Layout.Box(chat_history, { size = "90%" }),
		Layout.Box(chat_input, { size = "10%" }),
	}, { dir = "col" }),
}

local chat = Layout(chat_config.options, chat_config.box)

vim.api.nvim_create_autocmd("VimResized", {
	callback = function()
		chat:update(chat_config.options, chat_config.box)
	end,
})

-- handler for what to do when recieving a new update
---@type table<UpdateType, function>
local chat_update_handler = {}

chat_update_handler["agent_message_chunk"] = function(session_update)
	local content = session_update.content
	if content.type == "text" then
		local new_lines = vim.split(content.text, "\n")

		local last_line = vim.api.nvim_buf_get_lines(chat_history.bufnr, -2, -1, false)[1]

		new_lines[1] = last_line .. new_lines[1]

		vim.api.nvim_buf_set_lines(chat_history.bufnr, -2, -1, false, new_lines)
	else
		vim.notify("ui: unrecognized content type")
	end
end

---@param session_update JsonObject
local function update_chat(session_update)
	vim.api.nvim_buf_call(chat_history.bufnr, function()
		vim.cmd(":$")
	end)
	-- TODO:
	local handler = chat_update_handler[session_update.sessionUpdate]
	if handler then
		handler(session_update)
	end
end

---@param managed_session ManagedSession
---@param on_submit? fun(value:string)
function M.chat_open(managed_session, on_submit)
	local callback_ids = managed_session:on_update(function(json_response)
		update_chat(json_response)
	end)

	chat:mount()

	chat_input:on("QuitPre", function()
		M.chat_close(managed_session, callback_ids)
	end)
	chat_history:on("QuitPre", function()
		M.chat_close(managed_session, callback_ids)
	end)

	chat_history.border:set_text("top", managed_session.name, "center")

	vim.api.nvim_buf_call(chat_history.bufnr, function()
		vim.cmd(":set wrap")
	end)

	chat_input:map("i", "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(chat_input.bufnr, 0, -1, false)
		local flat_lines = Utils.flatten_str_arr(lines)
		vim.api.nvim_buf_set_lines(chat_input.bufnr, 0, -1, false, {})

		managed_session:prompt({ {
			text = flat_lines,
		} })

		if on_submit then
			on_submit(flat_lines)
		end
	end)
end

---@param lines string[]
function M.chat_append_input_text(lines)
	vim.api.nvim_buf_set_lines(chat_input.bufnr, -1, -1, false, lines)
end

---@param managed_session ManagedSession
function M.chat_close(managed_session, callback_ids)
	managed_session:del_update_callbacks(callback_ids)
	chat:unmount()
end

-- TODO: diff mode

return M

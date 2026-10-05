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

---@class Chat
---@field history NuiPopup
---@field input NuiPopup
---@field layout NuiLayout
---@field config table
---@field managed_session ManagedSession
---@field private update_callbacks UpdateInfo[]
---@field private autocmds table[]
local Chat = {}

---@param managed_session ManagedSession
---@return Chat
function Chat:new(managed_session)
	local chat = {}

	chat.managed_session = managed_session

	chat.autocmds = {}

	chat.update_callbacks = {}

	chat.history = Popup({
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

	chat.input = Popup({
		enter = true,
		focusable = true,
		border = "double",
	})

	chat.config = {
		options = {
			position = "50%",
			size = {
				width = "80%",
				height = "80%",
			},
		},
		box = Layout.Box({
			Layout.Box(chat.history, { size = "90%" }),
			Layout.Box(chat.input, { size = "10%" }),
		}, { dir = "col" }),
	}

	chat.layout = Layout(chat.config.options, chat.config.box)

	setmetatable(chat, { __index = self })

	return chat
end

--- autocommands to load when the chat is open and to unregister when chat is hidden or closed
---@param event string|string[]
---@param options table
function Chat:on(event, options)
	local id = vim.api.nvim_create_autocmd(event, options)
	table.insert(self.autocmds, { id = id, event = event, options = options })
end

---@param on_submit? fun(value:string)
function Chat:open(on_submit)
	self.layout:mount()

	self.update_callbacks = self.managed_session:on_update(function(json_response)
		self:update(json_response)
	end)

	self.history.border:set_text("top", self.managed_session.name, "center")

	vim.api.nvim_buf_call(self.history.bufnr, function()
		vim.cmd(":set wrap")
	end)

	self.input:map("i", "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(self.input.bufnr, 0, -1, false)
		local flat_lines = Utils.flatten_str_arr(lines)
		vim.api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, {})

		self.managed_session:prompt({ {
			text = flat_lines,
		} })

		if on_submit then
			on_submit(flat_lines)
		end
	end)
end

-- handler for what to do when recieving a new update
---@type table<UpdateType, function>
local chat_update_handler = {}

---@param chat Chat
---@param session_update JsonObject
chat_update_handler["agent_message_chunk"] = function(chat, session_update)
	local content = session_update.content
	if content.type == "text" then
		local new_lines = vim.split(content.text, "\n")

		local last_line = vim.api.nvim_buf_get_lines(chat.history.bufnr, -2, -1, false)[1]

		new_lines[1] = last_line .. new_lines[1]

		vim.api.nvim_buf_set_lines(chat.history.bufnr, -2, -1, false, new_lines)
	else
		vim.notify("ui: unrecognized content type")
	end
end

---@param session_update JsonObject
function Chat:update(session_update)
	vim.api.nvim_buf_call(self.history.bufnr, function()
		vim.cmd(":$")
	end)
	-- TODO:
	local handler = chat_update_handler[session_update.sessionUpdate]
	if handler then
		handler(self, session_update)
	end
end

function Chat:close()
	for _, autocmdinfo in ipairs(self.autocmds) do
		vim.api.nvim_del_autocmd(autocmdinfo.id)
	end

	self.managed_session:del_update_callbacks(self.update_callbacks)
	self.layout:unmount()
end

function Chat:hide()
	for _, autocmdinfo in ipairs(self.autocmds) do
		vim.api.nvim_del_autocmd(autocmdinfo.id)
	end
	self.layout:hide()
end

function Chat:show()
	for _, autocmdinfo in ipairs(self.autocmds) do
		autocmdinfo.id = vim.api.nvim_create_autocmd(autocmdinfo.event, autocmdinfo.options)
	end
	self.layout:show()
	vim.api.nvim_buf_call(self.history.bufnr, function()
		vim.cmd(":set wrap")
	end)
end

-- code to manage multiple active chat instances
-- we can only have one chat on screen at a time

---@type table<string, Chat>
local active_chats = {}

---@type Chat?
local open_chat = nil

---@param managed_session ManagedSession
function M.chat_open(managed_session)
	if open_chat then
		open_chat:hide()
		open_chat = nil
	end

	if active_chats[managed_session.name] then
		open_chat = active_chats[managed_session.name]
		open_chat:show()
	else
		local new_chat = Chat:new(managed_session)
		active_chats[managed_session.name] = new_chat
		new_chat:on("VimResized", {
			callback = function()
				new_chat.layout:update(new_chat.config.options, new_chat.config.box)
			end,
		})

		new_chat:on("QuitPre", {
			callback = function()
				M.chat_close()
			end,
		})

		open_chat = new_chat
		-- TODO: need a way to pass on_submit to open
		open_chat:open()
	end
end

---@param managed_session ManagedSession
function M.is_chat_open(managed_session)
	local chat = active_chats[managed_session.name]
	return open_chat == chat and chat ~= nil
end

---@param lines string[]
function M.chat_append_input_text(lines)
	if not open_chat then
		error("ui: cannot append to input; no open chat")
	end
	vim.api.nvim_buf_set_lines(open_chat.input.bufnr, -1, -1, false, lines)
end

function M.chat_close()
	if not open_chat then
		error("ui: cannot close; no open chat")
	end
	open_chat:close()
	local name = open_chat.managed_session.name
	active_chats[name] = nil
	open_chat = nil
end

function M.chat_hide()
	if not open_chat then
		error("ui: cannot close; no open chat")
	end
	open_chat:hide()
	open_chat = nil
end

-- TODO: diff mode

return M

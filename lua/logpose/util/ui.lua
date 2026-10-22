--- UI helpers shared by commands.
local M = {}

---@param err any
---@return string
function M.message(err)
  local msg = type(err) == "string" and err or vim.inspect(err)
  if not msg:find("^logpose:") then
    msg = "logpose: " .. msg
  end
  return msg
end

--- Whether a notifier plugin that shows titles (snacks, nvim-notify, noice) is in use.
---@return boolean
function M.titled_notifier()
  return package.loaded["snacks.notifier"] ~= nil or package.loaded["notify"] ~= nil or package.loaded["noice"] ~= nil
end

--- Notify with a "logpose" title. With a notifier that shows titles the "logpose: " prefix is
--- dropped (the title says it); with plain messages it's kept, so you know where it came from.
---@param msg string
---@param level? integer vim.log.levels
function M.notify(msg, level)
  msg = tostring(msg)
  if M.titled_notifier() then
    msg = msg:gsub("^logpose:%s*", "")
    msg = msg:sub(1, 1):upper() .. msg:sub(2)
  end
  vim.notify(msg, level or vim.log.levels.INFO, { title = "logpose" })
end

--- Wrap a callback (e.g. for vim.ui.input/select) so errors become notifications.
---@param fn function
---@return function
function M.safely(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      M.notify(M.message(err), vim.log.levels.ERROR)
    end
  end
end

--- Is `win` a window a screen shouldn't replace: a float, a window fixed to its buffer
--- ('winfixbuf'), or a plugin's side window (a snacks.nvim explorer, terminal or dashboard)?
---@param win integer
---@return boolean
local function special(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return true
  end
  if vim.fn.exists("+winfixbuf") == 1 and vim.wo[win].winfixbuf then
    return true
  end
  return vim.w[win].snacks_win ~= nil
end

--- Show `buf` (a logpose screen) in the current window, or in a regular one when the current
--- `lines` in a scratch buffer, in a split at the bottom; `q` closes it. Returns its window.
---@param lines string[]
---@param opts { name?: string, height?: integer, filetype?: string, locked?: boolean }
---@return integer win
function M.scratch(lines, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = not opts.locked
  vim.bo[buf].bufhidden = "wipe"
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  if opts.name then
    pcall(vim.api.nvim_buf_set_name, buf, opts.name)
  end
  vim.cmd(opts.height and ("botright %dsplit"):format(opts.height) or "botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
  return win
end

--- window is a float or a plugin's side window. The buffer can't be wiped while it is being shown
--- (a plugin moving it to another window hides it for a moment). Returns the window it's in.
---@param buf integer
---@return integer win
function M.show(buf)
  local cur = vim.api.nvim_get_current_win()
  if special(cur) then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if not special(win) then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end
  local hidden = vim.bo[buf].bufhidden
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_win_set_buf(0, buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].bufhidden = hidden
  end
  -- moved to another window by a plugin: go there
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 and win ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(win)
  end
  return vim.api.nvim_get_current_win()
end

return M

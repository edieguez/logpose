--- Dialogs (the edit form, peek, help windows) keep the focus while they're open. Going to a
--- window behind one (a click, <C-w>w, a plugin moving the cursor) comes straight back, so the
--- board can't be used under a form and a second form can't be opened from it. Floating windows
--- (pickers, completion docs, another dialog) are fine: they're opened from the dialog.
local M = {}

---@type integer[] open dialog windows, newest last
M.stack = {}

local function floating(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

--- The newest dialog still open.
---@return integer?
function M.top()
  for i = #M.stack, 1, -1 do
    local win = M.stack[i]
    if vim.api.nvim_win_is_valid(win) then
      return win
    end
    table.remove(M.stack, i)
  end
end

local function remove(win)
  for i = #M.stack, 1, -1 do
    if M.stack[i] == win then
      table.remove(M.stack, i)
    end
  end
end

local group
local function setup()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup("logpose.modal", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local top = M.top()
      local cur = vim.api.nvim_get_current_win()
      if not top or cur == top or floating(cur) then
        return
      end
      -- after whatever moved the focus has finished
      vim.schedule(function()
        local now = vim.api.nvim_get_current_win()
        if M.top() == top and now ~= top and not floating(now) then
          vim.api.nvim_set_current_win(top)
        end
      end)
    end,
  })
end

--- Keep the focus in `win` until it closes.
---@param win integer
function M.guard(win)
  setup()
  remove(win)
  table.insert(M.stack, win)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    once = true,
    callback = function()
      remove(win)
    end,
  })
end

return M

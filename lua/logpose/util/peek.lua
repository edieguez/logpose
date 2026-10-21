--- A note or task in a floating window: the file itself, to read and edit. `q` or <Esc> closes it
--- (saving changes); `on_close` runs after, with the index refreshed.
local M = {}

---@param file string
---@param title string
---@param on_close? fun()
---@return integer win
function M.open(file, title, on_close)
  local fit = require("logpose.board.text").fit
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  local width = math.min(90, math.max(40, math.floor(vim.o.columns * 0.6)))
  local height = math.min(30, math.max(8, math.floor((vim.o.lines - 2) * 0.7)))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - 2 - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = " " .. fit(title, width - 4):gsub("%s+$", "") .. " ",
    title_pos = "center",
    footer = " q close · changes are saved ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  -- Start at the body, after the frontmatter.
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local body = 1
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        body = math.min(i + 1, #lines)
        break
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, win, { body, 0 })
  -- Close keys for this window only: added to the buffer and removed when the float closes.
  local added = {}
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    if vim.fn.maparg(lhs, "n", false, true).buffer ~= 1 then
      vim.keymap.set("n", lhs, function()
        pcall(vim.api.nvim_win_close, win, false)
      end, { buffer = buf, nowait = true, silent = true, desc = "Close the peek window" })
      table.insert(added, lhs)
    end
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      for _, lhs in ipairs(added) do
        pcall(vim.keymap.del, "n", lhs, { buffer = buf })
      end
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        pcall(vim.api.nvim_buf_call, buf, function()
          vim.cmd("silent write")
        end)
      end
      vim.schedule(function()
        require("logpose.index").clear_cache()
        if on_close then
          on_close()
        end
      end)
    end,
  })
  return win
end

return M

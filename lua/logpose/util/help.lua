--- A help window: keys and the filter cheat sheet in a float. `q`, `<Esc>` or `?` closes it.
local M = {}

local ns = vim.api.nvim_create_namespace("logpose.help")

--- Show `lines` ({ text, highlight? }) in a centred float.
---@param title string
---@param lines { [1]: string, [2]?: string }[]
---@return integer win
function M.open(title, lines)
  local texts = vim.tbl_map(function(l)
    return l[1]
  end, lines)
  local width = 20
  for _, t in ipairs(texts) do
    width = math.max(width, vim.fn.strdisplaywidth(t) + 2)
  end
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#texts, vim.o.lines - 6)
  local buf = vim.api.nvim_create_buf(false, true)
  require("logpose.util.screen").draw(
    buf,
    ns,
    vim.tbl_map(function(l)
      return { l }
    end, lines)
  )
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "logpose-help"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - 2 - height) / 2)),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  require("logpose.util.modal").guard(win)
  for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", lhs, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true, silent = true })
  end
  return win
end

--- Lines for a list of keys: `{ "keys", "what" }` rows, and `{ "Heading" }` rows.
---@param rows table[]
---@return { [1]: string, [2]?: string }[]
function M.keys(rows)
  local w = 0
  for _, r in ipairs(rows) do
    if r[2] then
      w = math.max(w, vim.fn.strdisplaywidth(r[1]))
    end
  end
  local out = {}
  for _, r in ipairs(rows) do
    if r[2] then
      table.insert(out, { ("  %s%s  %s"):format(r[1], string.rep(" ", w - vim.fn.strdisplaywidth(r[1])), r[2]) })
    else
      if #out > 0 then
        table.insert(out, { "" })
      end
      table.insert(out, { r[1], "Title" })
    end
  end
  return out
end

--- Keys, then the filter cheat sheet.
---@param title string
---@param rows table[]
---@return integer win
function M.with_filters(title, rows)
  local lines = M.keys(rows)
  table.insert(lines, { "" })
  vim.list_extend(lines, require("logpose.filter").cheatsheet_lines())
  return M.open(title, lines)
end

return M

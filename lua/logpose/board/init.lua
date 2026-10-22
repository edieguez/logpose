--- `:Logpose board [filters]`: the task files as a Kanban board in a scratch buffer.
--- Columns come from `board.columns`; each card is a task file. Keys act on the focused card.
---
--- The board is split by concern: `text` (fitting text), `cards` (how a card looks), `collect`
--- (which cards), `view` (layout, drawing, refresh), `history` (undo/redo), `actions` (what keys
--- do) and `keys` (mappings). This module holds the open boards and opens new ones, and
--- re-exports the parts' functions so `require("logpose.board").x` keeps working.
local config = require("logpose.config")
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")
local view = require("logpose.board.view")
local keys = require("logpose.board.keys")
local parts = {
  require("logpose.board.text"),
  require("logpose.board.cards"),
  require("logpose.board.collect"),
  view,
  require("logpose.board.history"),
  require("logpose.board.actions"),
  keys,
}

local M = {}

---@class logpose.Board
---@field root string
---@field buf integer
---@field project? string active project when opened
---@field all boolean show every project
---@field filter string
---@field focus { col: integer, row: integer }
---@field columns { key: string, label: string, cards: logpose.Item[] }[]
---@field segments integer[][]  per buffer row: start byte of each column segment
---@field regions table<integer, { col: integer, row: integer }>[]  per buffer row (1-based): col -> card
---@field cards_at { first: integer, last: integer }[][]  [col][row] -> buffer rows (1-based)
---@field stacked boolean
---@field width integer column width
---@field widths integer[] width per column (folded ones are narrow)
---@field offset table<integer, integer> first visible card per column
---@field collapsed table<string, boolean> folded columns by key
---@field marked table<string, boolean> marked cards by file (v); actions apply to all of them

---@type table<integer, logpose.Board>
M.boards = {}

--- How long a moved card stays highlighted.
M.flash_ms = 300

--- Show the board in the current window: the one already open, as it was (filter, marks,
--- folded columns; it has followed project switches), or a new one.
---@param root string
---@return logpose.Board
function M.show(root)
  local existing = vim.fn.bufnr("logpose://board")
  local b = existing > 0 and M.boards[existing] or nil
  if b and b.root == root and vim.api.nvim_buf_is_valid(existing) then
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_get_current_buf() ~= existing then
      win = require("logpose.util.ui").show(existing)
    end
    view.setup_window(win)
    view.refresh(b, (view.focused(b) or {}).file)
    return b
  end
  return M.open_board(root)
end

--- Open a new board in the current window (replacing an open one).
---@param root string
---@param opts? { filter?: string, column?: string, project?: string }
---@return logpose.Board
function M.open_board(root, opts)
  opts = opts or {}
  local project = opts.project or require("logpose.project").resolve(root)
  local buf = ui.screen_buf("logpose://board", "logpose-board", "hide")
  vim.bo[buf].swapfile = false
  local tab, win
  if config.get().board.open == "tab" then
    vim.cmd("tabnew")
    tab = vim.api.nvim_get_current_tabpage()
    local scratch = vim.api.nvim_get_current_buf()
    win = require("logpose.util.ui").show(buf)
    if scratch ~= buf and vim.api.nvim_buf_get_name(scratch) == "" then
      pcall(vim.api.nvim_buf_delete, scratch, { force = true })
    end
  else
    win = require("logpose.util.ui").show(buf)
  end
  view.setup_window(win)
  ---@type logpose.Board
  local b = {
    root = root,
    buf = buf,
    project = project,
    all = project == nil,
    filter = opts.filter or "",
    focus = { col = 1, row = 1 },
    columns = {},
    segments = {},
    regions = {},
    cards_at = {},
    stacked = false,
    width = 0,
    widths = {},
    offset = {},
    undo = {},
    redo = {},
    tab = tab,
    compact = config.get().board.compact,
    lanes = config.get().board.lanes,
    marked = {},
    collapsed = {},
  }
  for _, key in ipairs(config.get().board.collapsed) do
    b.collapsed[key] = true
  end
  M.boards[buf] = b
  if opts.column then
    b.focus.col = taskfile.column_index(opts.column) or 1
  end
  keys.attach(b)
  local group = vim.api.nvim_create_augroup("logpose.board." .. buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      keys.on_cursor(b)
    end,
  })
  -- Coming back to the board: reload (files may have changed) and redraw.
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
        view.refresh(b, (view.focused(b) or {}).file)
      end
    end,
  })
  -- The active project changed (:Logpose project, the project manager): follow it.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LogposeProjectChanged",
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return true
      end
      b.project = require("logpose.project").resolve(root)
      b.all = b.project == nil
      b.focus = { col = b.focus.col, row = 1 }
      if vim.fn.bufwinid(buf) ~= -1 then
        view.refresh(b)
      end
    end,
  })
  -- Any window that starts showing the board gets the board's window options.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function()
      view.setup_window(vim.api.nvim_get_current_win())
      view.redraw_soon(b)
    end,
  })
  -- Size changes: the terminal, splits and sidebars opening or closing next to the board.
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "WinClosed", "WinNew" }, {
    group = group,
    callback = function(ev)
      if not vim.api.nvim_buf_is_valid(buf) then
        return true -- the board is gone: drop this autocmd
      end
      if ev.event == "WinResized" then
        local shown = false
        for _, win in ipairs((vim.v.event or {}).windows or {}) do
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            shown = true
          end
        end
        if not shown then
          return
        end
      end
      if vim.fn.bufwinid(buf) ~= -1 then
        view.redraw_soon(b)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      M.boards[buf] = nil
    end,
  })
  view.refresh(b)
  return b
end

--- Completion: the `find` filters.
function M.complete(arglead, args)
  return require("logpose.search").complete(arglead, vim.list_extend({ "tasks" }, args))
end

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    M.open_board(root, { filter = table.concat(opts.args, " ") })
  end))
end

-- The parts' functions and tables, so `require("logpose.board").render` and friends keep working.
-- (`project_hl` is left out: `cards` replaces that table on every refresh.)
for _, part in ipairs(parts) do
  for k, v in pairs(part) do
    if M[k] == nil and k ~= "project_hl" then
      M[k] = v
    end
  end
end

return M

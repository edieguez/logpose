--- What the board's keys do to the focused card: move, done, block, reorder, add, delete,
--- move to another project, peek, filter, close.
local config = require("logpose.config")
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")
local text = require("logpose.board.text")
local view = require("logpose.board.view")
local history = require("logpose.board.history")

local M = {}

---@param b logpose.Board
---@param name string
function M.count(b, name)
  require("logpose.telemetry").record("board", { name }, true)
end

--- The cards an action applies to: the marked ones (in board order), else the focused one.
---@param b logpose.Board
---@return logpose.Item[]
function M.targets(b)
  if next(b.marked) then
    local out = {}
    for _, col in ipairs(b.columns) do
      for _, it in ipairs(col.cards) do
        if b.marked[it.file] then
          table.insert(out, it)
        end
      end
    end
    if #out > 0 then
      return out
    end
  end
  local it = view.focused(b)
  return it and { it } or {}
end

--- What an action did to several cards, for the message after it.
local DID = {
  move = "moved",
  done = "done",
  block = "updated",
  project = "moved",
}

--- Run `fn` on each target card (the marked ones, or the focused one) as one undo step;
--- refresh after (keeping focus on the path `fn` returns, or the focused card).
---@param b logpose.Board
---@param name string telemetry keyword
---@param fn fun(it: logpose.Item): string|boolean|nil  return a path to follow, or false to skip
---@param suffix? string  added to the message after a bulk change ("to thesis")
local function with_card(b, name, fn, suffix)
  local targets = M.targets(b)
  if #targets == 0 then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  local before = history.snapshot(b)
  local changed, follow, err = 0, nil, nil
  for _, it in ipairs(targets) do
    local ok, res = pcall(fn, it)
    if not ok then
      err = res
      break
    end
    if res ~= false then
      changed = changed + 1
      follow = follow or (type(res) == "string" and res or it.file)
    end
  end
  history.record(b, name, before)
  if err then
    require("logpose.util.ui").notify(tostring(err), vim.log.levels.ERROR)
    if changed > 0 then
      view.refresh(b, (view.focused(b) or {}).file)
    end
    return
  end
  if changed == 0 then
    return
  end
  M.count(b, name)
  if #targets > 1 then
    view.refresh(b, (view.focused(b) or {}).file)
    require("logpose.util.ui").notify(
      ("logpose: %s %d of %d marked cards%s · u undoes"):format(
        DID[name] or "changed",
        changed,
        #targets,
        suffix and (" " .. suffix) or ""
      ),
      vim.log.levels.INFO
    )
    return
  end
  view.refresh(b, follow)
  if name == "move" or name == "done" then
    M.flash(b)
  end
end

--- `v`: mark or unmark the focused card, then go to the next one in the column.
---@param b logpose.Board
function M.toggle_mark(b)
  local it = view.focused(b)
  if not it then
    return
  end
  b.marked[it.file] = not b.marked[it.file] or nil
  M.count(b, "mark")
  local col = b.columns[b.focus.col]
  if col and b.focus.row < #col.cards then
    b.focus.row = b.focus.row + 1
  end
  view.highlight_focus(b)
  view.place_cursor(b)
end

--- `V` / `<Esc>`: unmark every card. Returns whether there were marks.
---@param b logpose.Board
---@return boolean
function M.clear_marks(b)
  if not next(b.marked) then
    return false
  end
  b.marked = {}
  view.highlight_focus(b)
  view.place_cursor(b)
  return true
end

local flash_ns = vim.api.nvim_create_namespace("logpose.board.flash")

--- Briefly highlight the focused card, so a move is easy to follow.
---@param b logpose.Board
function M.flash(b)
  local at = b.cards_at[b.focus.col] and b.cards_at[b.focus.col][b.focus.row]
  if not at then
    return
  end
  for row = at.first, at.last do
    local starts = b.segments[row] or {}
    local start = b.stacked and 0 or starts[b.focus.col]
    if start then
      local line = vim.api.nvim_buf_get_lines(b.buf, row - 1, row, false)[1] or ""
      local stop = (not b.stacked and starts[b.focus.col + 1]) and (starts[b.focus.col + 1] - 1) or #line
      pcall(vim.api.nvim_buf_set_extmark, b.buf, flash_ns, row - 1, start, {
        end_col = math.min(stop, #line),
        hl_group = "LogposeBoardFlash",
        priority = 300,
      })
    end
  end
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(b.buf) then
      vim.api.nvim_buf_clear_namespace(b.buf, flash_ns, 0, -1)
    end
  end, require("logpose.board").flash_ms)
end

--- Move the card(s) to column `target`.
---@param b logpose.Board
---@param target integer column index
function M.move_to(b, target)
  if target < 1 or target > #b.columns then
    return
  end
  with_card(b, "move", function(it)
    if b.columns[target].key == it.status then
      return false
    end
    taskfile.set_status(it.file, b.columns[target].key)
    return it.file
  end, "to " .. b.columns[target].label)
end

--- Move the card(s) `delta` columns left or right (each from its own column).
---@param b logpose.Board
---@param delta integer
function M.move(b, delta)
  with_card(b, "move", function(it)
    local target = (taskfile.column_index(it.status) or b.focus.col) + delta
    if target < 1 or target > #b.columns then
      return false
    end
    taskfile.set_status(it.file, b.columns[target].key)
    return it.file
  end)
end

---@param b logpose.Board
function M.done(b)
  local target = taskfile.column_index(config.get().board.done)
  with_card(b, "done", function(it)
    if it.status == config.get().board.done then
      return false
    end
    taskfile.set_status(it.file, b.columns[target].key)
    return it.file
  end)
end

---@param b logpose.Board
function M.toggle_block(b)
  local targets = M.targets(b)
  local it = targets[1]
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  if #targets > 1 then
    vim.ui.input(
      { prompt = ("Block %d cards by (empty unblocks): "):format(#targets) },
      ui.safely(function(reason)
        if reason == nil then
          return
        end
        reason = vim.trim(reason)
        with_card(b, "block", function(card)
          if (reason == "" and not card.blocked) or card.blocked == reason then
            return false
          end
          taskfile.set_blocked(card.file, reason ~= "" and reason or nil)
        end)
      end)
    )
    return
  end
  if it.blocked then
    with_card(b, "block", function(card)
      taskfile.set_blocked(card.file, nil)
    end)
    return
  end
  vim.ui.input(
    { prompt = "Blocked by: " },
    ui.safely(function(reason)
      if reason == nil then
        return
      end
      with_card(b, "block", function(card)
        taskfile.set_blocked(card.file, reason)
      end)
    end)
  )
end

--- Move the focused card to another project (asks which).
---@param b logpose.Board
function M.move_to_project(b)
  local targets = M.targets(b)
  local it = targets[1]
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  require("logpose.tasks").choose_project(b.root, #targets == 1 and it.project or nil, function(target)
    with_card(b, "project", function(card)
      if card.project == target then
        return false
      end
      taskfile.set_project(card.file, target)
    end, "to " .. (target or "no project"))
    if b.project and not b.all and target ~= b.project then
      require("logpose.util.ui").notify(
        ("logpose: moved to %s (p shows all projects)"):format(target or "no project"),
        vim.log.levels.INFO
      )
    end
  end)
end

--- Edit the focused card's frontmatter in a form; the change can be undone with `u`.
---@param b logpose.Board
function M.edit(b)
  local targets = M.targets(b)
  local it = targets[1]
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  local before = history.snapshot(b)
  if #targets > 1 then
    require("logpose.edit").open_bulk(
      vim.tbl_map(function(t)
        return t.file
      end, targets),
      {
        root = b.root,
        on_save = function(_, keys)
          if #keys == 0 then
            return
          end
          -- one undo step per save (the form stays open for more)
          history.record(b, "edit", before)
          before = history.snapshot(b)
          M.count(b, "edit")
          view.refresh(b, (view.focused(b) or {}).file)
        end,
      }
    )
    return
  end
  require("logpose.edit").open(it.file, {
    root = b.root,
    on_save = function(path, keys)
      if #keys == 0 then
        return
      end
      -- one undo step per save (the form stays open for more)
      history.record(b, "edit", before)
      before = history.snapshot(b)
      M.count(b, "edit")
      view.refresh(b, path)
    end,
  })
end

--- Swap the focused card with its neighbour `delta` places away.
---@param b logpose.Board
---@param delta integer
function M.reorder(b, delta)
  local col = b.columns[b.focus.col]
  local i, j = b.focus.row, b.focus.row + delta
  if not col.cards[i] or not col.cards[j] then
    return
  end
  with_card(b, "reorder", function(it)
    local cards = vim.list_extend({}, col.cards)
    cards[i], cards[j] = cards[j], cards[i]
    for n, card in ipairs(cards) do
      if card.order ~= n then
        taskfile.set_order(card.file, n)
      end
    end
    return it.file
  end)
end

--- Delete the focused card's task file (asks first).
---@param b logpose.Board
function M.delete(b)
  local it = view.focused(b)
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  vim.ui.select(
    { "Delete", "Cancel" },
    { prompt = ('Delete "%s"? The task file is removed.'):format(it.text) },
    ui.safely(function(choice)
      if choice ~= "Delete" then
        return
      end
      local fs = require("logpose.util.fs")
      local buf = fs.find_buf(it.file)
      if buf and vim.bo[buf].modified then
        error("logpose: the task file has unsaved changes; save or discard them first", 0)
      end
      local before = history.snapshot(b)
      local ok, err = os.remove(it.file)
      if not ok then
        error(("logpose: cannot delete %s: %s"):format(it.file, err), 0)
      end
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      require("logpose.index").clear_cache()
      history.record(b, "delete", before)
      M.count(b, "delete")
      require("logpose.util.ui").notify(("logpose: deleted %s"):format(vim.fs.basename(it.file)), vim.log.levels.INFO)
      view.refresh(b)
    end)
  )
end

---@param b logpose.Board
function M.add(b)
  local col = b.columns[b.focus.col]
  -- the project row the cursor is in, when cards are grouped by project; else the board's
  local project, source = (not b.all) and b.project or nil, "board"
  local lane = view.lane_at_cursor(b)
  if lane ~= nil then
    project, source = lane ~= "" and lane or nil, "lane"
  end
  local tasks = require("logpose.tasks")
  vim.ui.input(
    {
      prompt = ("New task in %s → %s: "):format(col.label, tasks.describe_project(project, source)),
      completion = "customlist,v:lua.require'logpose.tasks'.complete_input",
    },
    ui.safely(function(text)
      text = text and vim.trim(text) or ""
      if text == "" then
        return
      end
      local title, tags, due, explicit = taskfile.from_text(text)
      if explicit ~= nil then
        project = explicit or nil
      end
      tags = vim.tbl_filter(function(t)
        return t ~= project
      end, tags)
      local before = history.snapshot(b)
      local path =
        taskfile.create(b.root, { title = title, status = col.key, project = project, tags = tags, due = due })
      tasks.last = path
      history.record(b, "add", before)
      M.count(b, "add")
      view.refresh(b, path)
    end)
  )
end

---@param b logpose.Board
function M.open(b)
  local it = view.focused(b)
  if not it then
    return
  end
  M.count(b, "open")
  vim.cmd.edit(vim.fn.fnameescape(it.file))
end

--- Fold the focused column to a narrow strip, or unfold it.
---@param b logpose.Board
function M.toggle_fold(b)
  local col = b.columns[b.focus.col]
  if not col then
    return
  end
  b.collapsed[col.key] = not b.collapsed[col.key] or nil
  view.highlight_focus(b)
  view.place_cursor(b)
end

--- The focused task in a floating window: the file itself, so you can read and edit it.
--- `q` or <Esc> closes it (saving changes) and the board picks them up.
---@param b logpose.Board
---@return integer? win
function M.peek(b)
  local it = view.focused(b)
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  M.count(b, "peek")
  local buf = vim.fn.bufadd(it.file)
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
    title = " " .. text.fit(it.text, width - 4):gsub("%s+$", "") .. " ",
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
        if vim.api.nvim_buf_is_valid(b.buf) then
          require("logpose.index").clear_cache()
          view.refresh(b, it.file)
        end
      end)
    end,
  })
  return win
end

---@param b logpose.Board
function M.set_filter(b)
  vim.ui.input(
    { prompt = "Filter: ", default = b.filter },
    ui.safely(function(input)
      if input == nil then
        return
      end
      b.filter = vim.trim(input)
      view.refresh(b)
    end)
  )
end

---@param b logpose.Board
function M.close(b)
  local win = vim.fn.bufwinid(b.buf)
  -- Opened in its own tab: close the tab if the board is all that's in it.
  if win ~= -1 and b.tab and vim.api.nvim_tabpage_is_valid(b.tab) and #vim.api.nvim_list_tabpages() > 1 then
    if #vim.api.nvim_tabpage_list_wins(b.tab) == 1 then
      pcall(vim.api.nvim_buf_delete, b.buf, { force = true })
      return
    end
  end
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      local alt = vim.fn.bufnr("#")
      if alt > 0 and alt ~= b.buf and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
        vim.cmd.buffer(alt)
      else
        vim.cmd.enew()
      end
    end)
  end
  pcall(vim.api.nvim_buf_delete, b.buf, { force = true })
end

return M

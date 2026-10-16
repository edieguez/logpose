--- `:Logpose board [filters]`: the task files as a Kanban board in a scratch buffer.
--- Columns come from `board.columns`; each card is a task file. Keys act on the focused card.
local config = require("logpose.config")
local date = require("logpose.util.date")
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.board")

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

---@type table<integer, logpose.Board>
M.boards = {}

M.HELP = {
  "logpose board",
  "  h / l        previous / next column      j / k   previous / next card",
  "  H / L  < >   move the card left / right  1-9     move it to column N",
  "  x            done                        b       block / unblock",
  "  J / K        move the card down / up     a       add a card here",
  "  D            delete the card (asks)",
  "  <CR>         open the task file          /       filter (find filters)",
  "  p            this project / all          r       refresh",
  "  q            close                       ?       this help",
}

--- Text cut or padded to exactly `w` display cells.
---@param s string
---@param w integer
---@return string
function M.fit(s, w)
  if w <= 0 then
    return ""
  end
  local width = vim.fn.strdisplaywidth(s)
  if width <= w then
    return s .. string.rep(" ", w - width)
  end
  local out, used = {}, 0
  local n = vim.fn.strchars(s)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local cw = vim.fn.strdisplaywidth(ch)
    if used + cw > w - 1 then
      break
    end
    table.insert(out, ch)
    used = used + cw
  end
  return table.concat(out) .. "…" .. string.rep(" ", w - used - 1)
end

--- Word-wrap `s` into at most `max` lines of `w` cells (the last one cut with …).
---@param s string
---@param w integer
---@param max integer
---@return string[]
function M.wrap(s, w, max)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    local candidate = cur == "" and word or (cur .. " " .. word)
    if vim.fn.strdisplaywidth(candidate) <= w or cur == "" then
      cur = candidate
    else
      table.insert(lines, cur)
      cur = word
    end
  end
  if cur ~= "" then
    table.insert(lines, cur)
  end
  if #lines > max then
    local rest = table.concat(vim.list_slice(lines, max), " ")
    lines = vim.list_slice(lines, 1, max - 1)
    table.insert(lines, rest)
  end
  for i, l in ipairs(lines) do
    if vim.fn.strdisplaywidth(l) > w then
      lines[i] = vim.trim(M.fit(l, w))
    end
  end
  return #lines > 0 and lines or { "" }
end

--- First day whose Done tasks are still shown.
---@param today string
---@return string
local function done_since(today)
  local window = config.get().board.done_window
  if window == "period" then
    return require("logpose.period").of(today).start
  end
  return date.add_days(today, -(window - 1))
end

---@param a logpose.Item
---@param b logpose.Item
local function card_order(a, b)
  local oa, ob = a.order or math.huge, b.order or math.huge
  if oa ~= ob then
    return oa < ob
  end
  local da, db = a.due or "9999", b.due or "9999"
  if da ~= db then
    return da < db
  end
  local ca, cb = a.created or "", b.created or ""
  if ca ~= cb then
    return ca < cb
  end
  return a.file < b.file
end

--- Task items on the board, by column.
---@param root string
---@param opts { project?: string, filter?: string, today?: string }
---@return { key: string, label: string, cards: logpose.Item[] }[]
function M.collect(root, opts)
  local index = require("logpose.index")
  local query = require("logpose.query")
  local today = opts.today or date.today()
  local q = query.parse(query.split(opts.filter or ""), today, true)
  local cfg = config.get()
  local orders = {}
  for _, t in ipairs(taskfile.list(root)) do
    orders[t.path] = t.order
  end
  local columns, by_key = {}, {}
  for _, c in ipairs(taskfile.columns()) do
    local col = { key = c.key, label = c.label, cards = {} }
    table.insert(columns, col)
    by_key[c.key] = col
  end
  local since = done_since(today)
  for _, it in ipairs(index.build(root)) do
    if it.kind == "note" and it.note_type == "task" and not it.archived then
      local in_scope = not opts.project or it.project == opts.project or vim.tbl_contains(it.tags, opts.project)
      local recent = it.status ~= cfg.board.done or not it.done_date or it.done_date >= since
      if in_scope and recent and query.match(it, q) then
        it.order = orders[it.file]
        local col = by_key[it.status] or by_key[cfg.tasks.capture_status]
        table.insert(col.cards, it)
      end
    end
  end
  for _, col in ipairs(columns) do
    table.sort(col.cards, card_order)
  end
  return columns
end

--- Highlight groups, linked to standard groups so colour schemes style them; override any with
--- `vim.api.nvim_set_hl(0, "LogposeBoard…", {...})`.
M.HL = {
  LogposeBoardTitle = "Title",
  LogposeBoardHint = "Comment",
  LogposeBoardFocus = "Special",
  LogposeBoardFocusTitle = { bold = true },
  LogposeBoardProject = "Identifier",
  LogposeBoardTag = "Label",
  LogposeBoardDue = "Comment",
  LogposeBoardOverdue = "DiagnosticError",
  LogposeBoardBlocked = "DiagnosticError",
  LogposeBoardEmpty = "Comment",
}
--- Column colours by position (a column's `hl` overrides): grey, blue, yellow, purple, green.
M.COLUMN_HL = { "Comment", "DiagnosticInfo", "DiagnosticWarn", "DiagnosticHint", "DiagnosticOk" }

local function define_highlights()
  for name, link in pairs(M.HL) do
    local spec = type(link) == "table" and vim.tbl_extend("force", { default = true }, link)
      or { link = link, default = true }
    vim.api.nvim_set_hl(0, name, spec)
  end
  for i, col in ipairs(config.get().board.columns) do
    local link = col.hl or M.COLUMN_HL[(i - 1) % #M.COLUMN_HL + 1]
    vim.api.nvim_set_hl(0, "LogposeBoardColumn" .. i, { link = link, default = true })
  end
end

local BOX = {
  normal = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
  focus = { tl = "┏", tr = "┓", bl = "┗", br = "┛", h = "━", v = "┃" },
}

---@alias logpose.Chunk { [1]: string, [2]: string? }  text, highlight group

--- Chunks cut or padded to exactly `w` display cells.
---@param chunks logpose.Chunk[]
---@param w integer
---@return logpose.Chunk[]
function M.fit_chunks(chunks, w)
  local out, used = {}, 0
  for _, c in ipairs(chunks) do
    local cw = vim.fn.strdisplaywidth(c[1])
    if used + cw <= w then
      table.insert(out, c)
      used = used + cw
    else
      local room = w - used
      if room > 0 then
        table.insert(out, { vim.trim(M.fit(c[1], room)), c[2] })
        used = used + vim.fn.strdisplaywidth(out[#out][1])
      end
      break
    end
  end
  if used < w then
    table.insert(out, { string.rep(" ", w - used) })
  end
  return out
end

--- One card as box lines of `w` cells. Each line is a list of chunks.
---@param it logpose.Item
---@param w integer
---@param today string
---@param col_hl string the column's highlight group
---@param focused boolean
---@return logpose.Chunk[][]
function M.card_lines(it, w, today, col_hl, focused)
  local box = focused and BOX.focus or BOX.normal
  local border = focused and "LogposeBoardFocus" or (it.blocked and "LogposeBoardBlocked" or col_hl)
  local inner = math.max(w - 4, 1)
  local out = {}
  local function row(chunks)
    local line = { { box.v .. " ", border } }
    vim.list_extend(line, M.fit_chunks(chunks, inner))
    table.insert(line, { " " .. box.v, border })
    table.insert(out, line)
  end
  table.insert(out, { { box.tl .. string.rep(box.h, w - 2) .. box.tr, border } })
  for _, l in ipairs(M.wrap(it.text, inner, 2)) do
    row({ { l, focused and "LogposeBoardFocusTitle" or nil } })
  end
  if it.blocked then
    row({ { "⊘ " .. (it.blocked == "yes" and "blocked" or it.blocked), "LogposeBoardBlocked" } })
  end
  local meta = {}
  local function add(text, hl)
    if #meta > 0 then
      table.insert(meta, { " " })
    end
    table.insert(meta, { text, hl })
  end
  if it.project then
    add("◆ " .. it.project, "LogposeBoardProject")
  end
  for _, t in ipairs(it.tags or {}) do
    if t ~= it.project then
      add("#" .. t, "LogposeBoardTag")
    end
  end
  if it.due then
    local overdue = it.due < today and it.status ~= config.get().board.done
    add("◷ " .. it.due:sub(6), overdue and "LogposeBoardOverdue" or "LogposeBoardDue")
  end
  if #meta > 0 then
    row(meta)
  end
  table.insert(out, { { box.bl .. string.rep(box.h, w - 2) .. box.br, border } })
  return out
end

--- Render into the board buffer and remember where each card is.
---@param b logpose.Board
---@param width integer window width
function M.render(b, width)
  define_highlights()
  local today = date.today()
  local cfg = config.get().board
  local n = #b.columns
  local colw = math.floor((width - (n - 1)) / n)
  b.stacked = colw < cfg.min_column_width
  b.width = b.stacked and math.max(width - 1, 20) or colw

  local scope = b.all and "all projects" or (b.project or "all projects")
  local head = { { "Board", "LogposeBoardTitle" }, { " · " .. scope, "LogposeBoardProject" } }
  if b.filter ~= "" then
    table.insert(head, { " · " .. b.filter, "LogposeBoardHint" })
  end
  table.insert(head, { "    ? help", "LogposeBoardHint" })
  local lines, hls = {}, {}
  b.segments, b.regions, b.cards_at = {}, {}, {}

  --- Append a buffer row from per-column chunk lists; records highlights and card regions.
  ---@param segs { chunks: logpose.Chunk[], ci?: integer, card?: integer }[]
  local function add_row(segs)
    local row = #lines + 1
    local parts, starts, region = {}, {}, {}
    local offset = 0
    for i, seg in ipairs(segs) do
      if i > 1 then
        table.insert(parts, " ")
        offset = offset + 1
      end
      starts[i] = offset
      for _, c in ipairs(seg.chunks) do
        table.insert(parts, c[1])
        if c[2] then
          table.insert(hls, { row = row, col = offset, len = #c[1], hl = c[2] })
        end
        offset = offset + #c[1]
      end
      if seg.card then
        region[seg.ci] = { col = seg.ci, row = seg.card }
        local at = b.cards_at[seg.ci][seg.card]
        if at then
          at.last = row
        else
          b.cards_at[seg.ci][seg.card] = { first = row, last = row }
        end
      end
    end
    lines[row] = (table.concat(parts):gsub("%s+$", "")) -- no trailing whitespace, ever
    b.segments[row] = starts
    b.regions[row] = region
  end

  add_row({ { chunks = head } })
  add_row({ { chunks = {} } })

  -- Each column as a list of segments of width b.width.
  local blocks = {}
  for ci, col in ipairs(b.columns) do
    local col_hl = "LogposeBoardColumn" .. ci
    local block = {}
    table.insert(block, {
      chunks = M.fit_chunks({
        { "● ", col_hl },
        { col.label, col_hl },
        { (" (%d)"):format(#col.cards), "LogposeBoardHint" },
      }, b.width),
    })
    b.cards_at[ci] = {}
    if #col.cards == 0 then
      table.insert(block, { chunks = M.fit_chunks({ { "  · empty ·", "LogposeBoardEmpty" } }, b.width) })
    end
    for ri, it in ipairs(col.cards) do
      local focused = ci == b.focus.col and ri == b.focus.row
      for _, l in ipairs(M.card_lines(it, b.width, today, col_hl, focused)) do
        table.insert(block, { chunks = l, card = ri })
      end
    end
    blocks[ci] = block
  end

  if b.stacked then
    for ci, block in ipairs(blocks) do
      for _, seg in ipairs(block) do
        seg.ci = ci
        add_row({ seg })
        b.segments[#lines] = { 0 }
        b.regions[#lines].stack_col = ci
      end
      if ci < #blocks then
        add_row({ { chunks = {}, ci = ci } })
        b.regions[#lines].stack_col = ci
      end
    end
  else
    local height = 0
    for _, block in ipairs(blocks) do
      height = math.max(height, #block)
    end
    local blank = { { string.rep(" ", b.width) } }
    for r = 1, height do
      local segs = {}
      for ci, block in ipairs(blocks) do
        local seg = block[r] or { chunks = blank }
        segs[ci] = { chunks = seg.chunks, card = seg.card, ci = ci }
      end
      add_row(segs)
    end
  end

  local win = vim.fn.bufwinid(b.buf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
  vim.bo[b.buf].modifiable = true
  vim.api.nvim_buf_set_lines(b.buf, 0, -1, false, lines)
  vim.bo[b.buf].modifiable = false
  vim.bo[b.buf].modified = false
  if cursor then
    b._placing = true
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
    b._placing = false
  end
  vim.api.nvim_buf_clear_namespace(b.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local len = #(lines[h.row] or "")
    if h.col < len then
      pcall(vim.api.nvim_buf_set_extmark, b.buf, ns, h.row - 1, h.col, {
        end_col = math.min(h.col + h.len, len),
        hl_group = h.hl,
      })
    end
  end
end

--- Column and card under a buffer position.
---@param b logpose.Board
---@param row integer 1-based
---@param col integer 0-based byte
---@return integer? col, integer? card
function M.at(b, row, col)
  local region = b.regions[row]
  if not region then
    return nil
  end
  local ci
  if b.stacked then
    ci = region.stack_col
  else
    local starts = b.segments[row] or {}
    for i = #starts, 1, -1 do
      if col >= starts[i] then
        ci = i
        break
      end
    end
  end
  if not ci then
    return nil
  end
  return ci, region[ci] and region[ci].row or nil
end

---@param b logpose.Board
---@return logpose.Item?
function M.focused(b)
  local col = b.columns[b.focus.col]
  return col and col.cards[b.focus.row]
end

--- Keep the focus inside the board.
---@param b logpose.Board
local function clamp(b)
  b.focus.col = math.max(1, math.min(b.focus.col, #b.columns))
  local count = #b.columns[b.focus.col].cards
  b.focus.row = math.max(1, math.min(b.focus.row, math.max(count, 1)))
end

--- Redraw so the focused card gets the heavy border.
---@param b logpose.Board
function M.highlight_focus(b)
  local win = vim.fn.bufwinid(b.buf)
  M.render(b, win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns)
end

--- Put the cursor on the focused card (or the column header when it's empty).
---@param b logpose.Board
local function place_cursor(b)
  local win = vim.fn.bufwinid(b.buf)
  if win == -1 then
    return
  end
  local at = b.cards_at[b.focus.col] and b.cards_at[b.focus.col][b.focus.row]
  local row = at and at.first + 1 -- the title line, inside the box
  local inside = at and #(BOX.normal.v .. " ") or 0
  if not row then
    -- the column header
    for r, region in pairs(b.regions) do
      if b.stacked and region.stack_col == b.focus.col then
        row = row and math.min(row, r) or r
      end
    end
    row = row or 3
  end
  local col = (b.stacked and 0 or ((b.segments[row] or {})[b.focus.col] or 0)) + inside
  b._placing = true
  pcall(vim.api.nvim_win_set_cursor, win, { row, col })
  b._placing = false
end

--- Reload the cards from disk and redraw, keeping the focus on `path` when given.
---@param b logpose.Board
---@param path? string
function M.refresh(b, path)
  b.columns = M.collect(b.root, { project = (not b.all) and b.project or nil, filter = b.filter })
  if path then
    for ci, col in ipairs(b.columns) do
      for ri, it in ipairs(col.cards) do
        if it.file == path then
          b.focus = { col = ci, row = ri }
        end
      end
    end
  end
  clamp(b)
  local win = vim.fn.bufwinid(b.buf)
  M.render(b, win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns)
  place_cursor(b)
end

---@param b logpose.Board
---@param name string
local function count(b, name)
  require("logpose.telemetry").record("board", { name }, true)
end

--- Run `fn` with the focused card; refresh after (keeping focus on `follow` or the card).
---@param b logpose.Board
---@param name string telemetry keyword
---@param fn fun(it: logpose.Item): string|boolean|nil  return a path to follow, or false to skip
local function with_card(b, name, fn)
  local it = M.focused(b)
  if not it then
    vim.notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  local ok, res = pcall(fn, it)
  if not ok then
    vim.notify(tostring(res), vim.log.levels.ERROR)
    return
  end
  if res == false then
    return
  end
  count(b, name)
  M.refresh(b, type(res) == "string" and res or it.file)
end

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
  end)
end

---@param b logpose.Board
---@param delta integer
function M.move(b, delta)
  M.move_to(b, b.focus.col + delta)
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
  local it = M.focused(b)
  if not it then
    vim.notify("logpose: no card here", vim.log.levels.INFO)
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
  local it = M.focused(b)
  if not it then
    vim.notify("logpose: no card here", vim.log.levels.INFO)
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
      local ok, err = os.remove(it.file)
      if not ok then
        error(("logpose: cannot delete %s: %s"):format(it.file, err), 0)
      end
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      require("logpose.index").clear_cache()
      count(b, "delete")
      vim.notify(("logpose: deleted %s"):format(vim.fs.basename(it.file)), vim.log.levels.INFO)
      M.refresh(b)
    end)
  )
end

---@param b logpose.Board
function M.add(b)
  local col = b.columns[b.focus.col]
  vim.ui.input(
    { prompt = ("New task in %s: "):format(col.label) },
    ui.safely(function(title)
      title = title and vim.trim(title) or ""
      if title == "" then
        return
      end
      local project = (not b.all) and b.project or nil
      local path = taskfile.create(b.root, { title = title, status = col.key, project = project })
      count(b, "add")
      M.refresh(b, path)
    end)
  )
end

---@param b logpose.Board
function M.open(b)
  local it = M.focused(b)
  if not it then
    return
  end
  count(b, "open")
  vim.cmd.edit(vim.fn.fnameescape(it.file))
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
      M.refresh(b)
    end)
  )
end

---@param b logpose.Board
function M.close(b)
  local win = vim.fn.bufwinid(b.buf)
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

---@param b logpose.Board
local function on_cursor(b)
  if b._placing then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local ci, ri = M.at(b, pos[1], pos[2])
  if ci and ri and (ci ~= b.focus.col or ri ~= b.focus.row) then
    b.focus = { col = ci, row = ri }
    M.highlight_focus(b)
  elseif ci and not ri and ci ~= b.focus.col then
    b.focus = { col = ci, row = 1 }
    clamp(b)
    M.highlight_focus(b)
  end
end

---@param b logpose.Board
local function keymaps(b)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = b.buf, nowait = true, silent = true, desc = desc })
  end
  local function step(dc, dr)
    return function()
      b.focus.col = b.focus.col + dc
      b.focus.row = b.focus.row + dr
      clamp(b)
      M.highlight_focus(b)
      place_cursor(b)
    end
  end
  map("h", step(-1, 0), "Previous column")
  map("l", step(1, 0), "Next column")
  map("j", step(0, 1), "Next card")
  map("k", step(0, -1), "Previous card")
  map("<Left>", step(-1, 0), "Previous column")
  map("<Right>", step(1, 0), "Next column")
  map("<Down>", step(0, 1), "Next card")
  map("<Up>", step(0, -1), "Previous card")
  for _, lhs in ipairs({ "H", "<" }) do
    map(lhs, function()
      M.move(b, -1)
    end, "Move card left")
  end
  for _, lhs in ipairs({ "L", ">" }) do
    map(lhs, function()
      M.move(b, 1)
    end, "Move card right")
  end
  for i = 1, math.min(9, #taskfile.columns()) do
    map(tostring(i), function()
      M.move_to(b, i)
    end, "Move card to column " .. i)
  end
  map("x", function()
    M.done(b)
  end, "Done")
  map("b", function()
    M.toggle_block(b)
  end, "Block / unblock")
  map("J", function()
    M.reorder(b, 1)
  end, "Move card down")
  map("K", function()
    M.reorder(b, -1)
  end, "Move card up")
  map("a", function()
    M.add(b)
  end, "Add card")
  map("D", function()
    M.delete(b)
  end, "Delete card")
  map("<CR>", function()
    M.open(b)
  end, "Open task")
  map("<2-LeftMouse>", function()
    on_cursor(b)
    M.open(b)
  end, "Open task")
  map("/", function()
    M.set_filter(b)
  end, "Filter")
  map("p", function()
    b.all = not b.all
    M.refresh(b, (M.focused(b) or {}).file)
  end, "This project / all")
  map("r", function()
    M.refresh(b, (M.focused(b) or {}).file)
  end, "Refresh")
  map("q", function()
    M.close(b)
  end, "Close")
  map("?", function()
    vim.notify(table.concat(M.HELP, "\n"), vim.log.levels.INFO)
  end, "Help")
end

--- Open the board in the current window.
---@param root string
---@param opts? { filter?: string, column?: string }
---@return logpose.Board
function M.open_board(root, opts)
  opts = opts or {}
  local project = require("logpose.project").resolve(root)
  local name = "logpose://board"
  local existing = vim.fn.bufnr(name)
  if existing > 0 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "logpose-board"
  vim.api.nvim_win_set_buf(0, buf)
  for opt, value in pairs({ wrap = false, number = false, relativenumber = false, signcolumn = "no", list = false }) do
    vim.wo[0][0][opt] = value
  end
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
  }
  M.boards[buf] = b
  if opts.column then
    b.focus.col = taskfile.column_index(opts.column) or 1
  end
  keymaps(b)
  local group = vim.api.nvim_create_augroup("logpose.board." .. buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      on_cursor(b)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "VimResized" }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
        M.refresh(b, (M.focused(b) or {}).file)
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
  M.refresh(b)
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

return M

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
---@field widths integer[] width per column (folded ones are narrow)
---@field offset table<integer, integer> first visible card per column
---@field collapsed table<string, boolean> folded columns by key

---@type table<integer, logpose.Board>
M.boards = {}

M.HELP = {
  "logpose board",
  "  h / l        previous / next column      j / k   previous / next card",
  "  H / L  < >   move the card left / right  1-9     move it to column N",
  "  x            done                        b       block / unblock",
  "  <C-j>/<C-k>  move the card down / up     a       add a card here",
  "  K            peek: the task in a float   D       delete the card (asks)",
  "  <CR>         open the task file          /       filter (find filters)",
  "  z            fold / unfold the column    gg / G  first / last card",
  "  u / <C-r>    undo / redo a board change",
  "  c            compact cards on / off      s       rows per project on / off",
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
  -- "…" marks the cut; ASCII icons use "~" so the board stays plain ASCII.
  local ellipsis = config.get().board.icons == "ascii" and "~" or "…"
  return table.concat(out) .. ellipsis .. string.rep(" ", w - used - 1)
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
  local orders, since_of = {}, {}
  for _, t in ipairs(taskfile.list(root)) do
    orders[t.path] = t.order
    since_of[t.path] = t.since
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
        it.since = since_of[it.file]
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
  LogposeBoardAge = "Comment",
  LogposeBoardStale = "DiagnosticWarn",
  LogposeBoardFaded = "Comment",
  LogposeBoardOverLimit = "DiagnosticError",
  LogposeBoardMore = "Comment",
  LogposeBoardFlash = "IncSearch",
}
--- Column colours by position (a column's `hl` overrides): grey, blue, yellow, purple, green.
M.COLUMN_HL = { "Comment", "DiagnosticInfo", "DiagnosticWarn", "DiagnosticHint", "DiagnosticOk" }

--- Width of a folded column.
M.COLLAPSED_WIDTH = 5

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

local UNICODE_BOX = {
  normal = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
  focus = { tl = "┏", tr = "┓", bl = "┗", br = "┛", h = "━", v = "┃" },
}

--- Glyph sets (`board.icons`): "unicode" works in any UTF-8 terminal, "nerd" needs a Nerd Font,
--- "ascii" works everywhere.
M.ICONS = {
  unicode = {
    project = "◆",
    due = "◷",
    blocked = "⊘",
    column = "●",
    folded = "▸",
    up = "↑",
    down = "↓",
    focus = "▶",
    card = "•",
    empty = "· empty ·",
    box = UNICODE_BOX,
  },
  nerd = {
    project = "",
    due = "",
    blocked = "",
    column = "",
    folded = "",
    up = "",
    down = "",
    focus = "",
    card = "•",
    empty = "· empty ·",
    box = UNICODE_BOX,
  },
  ascii = {
    project = "+",
    due = "due",
    blocked = "!",
    column = "*",
    folded = ">",
    up = "^",
    down = "v",
    focus = ">",
    card = "-",
    empty = "- empty -",
    box = {
      normal = { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|" },
      focus = { tl = "#", tr = "#", bl = "#", br = "#", h = "=", v = "#" },
    },
  },
}

---@return table
local function icons()
  return M.ICONS[config.get().board.icons] or M.ICONS.unicode
end

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

--- Days a card has been in its column (nil in Done).
---@param it logpose.Item
---@param today string
---@return integer?
function M.age(it, today)
  if it.status == config.get().board.done or not it.since or not date.is_iso(it.since) then
    return nil
  end
  return math.max(0, date.diff_days(it.since, today))
end

--- One card as box lines of `w` cells. Each line is a list of chunks.
---@param it logpose.Item
---@param w integer
---@param today string
---@param col_hl string the column's highlight group
---@param focused boolean
---@param compact? boolean one line, no box
---@return logpose.Chunk[][]
function M.card_lines(it, w, today, col_hl, focused, compact)
  local ic = icons()
  if compact then
    return { M.compact_line(it, w, today, col_hl, focused) }
  end
  local box = focused and ic.box.focus or ic.box.normal
  local border = focused and "LogposeBoardFocus" or (it.blocked and "LogposeBoardBlocked" or col_hl)
  local inner = math.max(w - 4, 1)
  local age = M.age(it, today)
  local stale = age and age >= config.get().board.stale_days
  local out = {}
  local function row(chunks)
    local line = { { box.v .. " ", border } }
    vim.list_extend(line, M.fit_chunks(chunks, inner))
    table.insert(line, { " " .. box.v, border })
    table.insert(out, line)
  end
  table.insert(out, { { box.tl .. string.rep(box.h, w - 2) .. box.tr, border } })
  local title_hl = focused and "LogposeBoardFocusTitle" or (stale and "LogposeBoardFaded" or nil)
  for _, l in ipairs(M.wrap(it.text, inner, 2)) do
    row({ { l, title_hl } })
  end
  if it.blocked then
    row({ { ic.blocked .. " " .. (it.blocked == "yes" and "blocked" or it.blocked), "LogposeBoardBlocked" } })
  end
  local meta = {}
  local function add(text, hl)
    if #meta > 0 then
      table.insert(meta, { " " })
    end
    table.insert(meta, { text, hl })
  end
  if it.project then
    add(ic.project .. " " .. it.project, "LogposeBoardProject")
  end
  for _, t in ipairs(it.tags or {}) do
    if t ~= it.project then
      add("#" .. t, "LogposeBoardTag")
    end
  end
  if it.due then
    local overdue = it.due < today and it.status ~= config.get().board.done
    add(ic.due .. " " .. it.due:sub(6), overdue and "LogposeBoardOverdue" or "LogposeBoardDue")
  end
  if age then
    add(("%dd"):format(age), stale and "LogposeBoardStale" or "LogposeBoardAge")
  end
  if #meta > 0 then
    row(meta)
  end
  table.insert(out, { { box.bl .. string.rep(box.h, w - 2) .. box.br, border } })
  return out
end

--- A card on one line: a marker (▶ when focused, ⊘ when blocked), the title, then the due date
--- and age at the end.
---@param it logpose.Item
---@param w integer
---@param today string
---@param col_hl string
---@param focused boolean
---@return logpose.Chunk[]
function M.compact_line(it, w, today, col_hl, focused)
  local ic = icons()
  local marker, marker_hl = ic.card, col_hl
  if it.blocked then
    marker, marker_hl = ic.blocked, "LogposeBoardBlocked"
  end
  if focused then
    marker, marker_hl = ic.focus, "LogposeBoardFocus"
  end
  local tail = {}
  if it.due then
    local overdue = it.due < today and it.status ~= config.get().board.done
    table.insert(
      tail,
      { " " .. ic.due .. " " .. it.due:sub(6), overdue and "LogposeBoardOverdue" or "LogposeBoardDue" }
    )
  end
  local age = M.age(it, today)
  local stale = age and age >= config.get().board.stale_days
  if age then
    table.insert(tail, { (" %dd"):format(age), stale and "LogposeBoardStale" or "LogposeBoardAge" })
  end
  local tail_w = 0
  for _, c in ipairs(tail) do
    tail_w = tail_w + vim.fn.strdisplaywidth(c[1])
  end
  local title_w = math.max(w - 2 - tail_w, 1)
  local title_hl = focused and "LogposeBoardFocusTitle" or (stale and "LogposeBoardFaded" or nil)
  local line = { { marker .. " ", marker_hl }, { M.fit(it.text, title_w), title_hl } }
  vim.list_extend(line, tail)
  return M.fit_chunks(line, w)
end

--- Lines of one column: header, then the cards that fit (scrolled so the focused one shows),
--- with "↑ n more" / "↓ n more" markers. Records which cards are visible.
---@param b logpose.Board
---@param ci integer
---@param w integer
---@param avail integer rows available under the header
---@param today string
---@return { chunks: logpose.Chunk[], card?: integer }[]
local function column_block(b, ci, w, avail, today)
  local col = b.columns[ci]
  local col_hl = "LogposeBoardColumn" .. ci
  local limit = config.get().board.columns[ci] and config.get().board.columns[ci].limit
  local over = limit and #col.cards > limit
  local block = {}
  if b.collapsed[col.key] then
    table.insert(block, {
      chunks = M.fit_chunks(
        { { icons().folded, col_hl }, { tostring(#col.cards), over and "LogposeBoardOverLimit" or "LogposeBoardHint" } },
        w
      ),
    })
    -- The label, one letter per line.
    local n = vim.fn.strchars(col.label)
    for i = 0, math.min(n, avail) - 1 do
      table.insert(block, { chunks = M.fit_chunks({ { " " .. vim.fn.strcharpart(col.label, i, 1), col_hl } }, w) })
    end
    return block
  end
  local count = limit and ("(%d/%d)"):format(#col.cards, limit) or ("(%d)"):format(#col.cards)
  table.insert(block, {
    chunks = M.fit_chunks({
      { icons().column .. " ", col_hl },
      { col.label .. " ", col_hl },
      { count, over and "LogposeBoardOverLimit" or "LogposeBoardHint" },
    }, w),
  })
  if #col.cards == 0 then
    table.insert(block, { chunks = M.fit_chunks({ { "  " .. icons().empty, "LogposeBoardEmpty" } }, w) })
    return block
  end
  local lines = {}
  for ri, it in ipairs(col.cards) do
    lines[ri] = M.card_lines(it, w, today, col_hl, ci == b.focus.col and ri == b.focus.row, b.compact)
  end
  -- Do cards first..last fit, counting the "more" markers they'd need?
  local function fits(first, last)
    local rows = (first > 1 and 1 or 0) + (last < #lines and 1 or 0)
    for r = first, last do
      rows = rows + #lines[r]
    end
    return rows <= avail
  end
  local first = math.max(1, math.min(b.offset[ci] or 1, #lines))
  if ci == b.focus.col then
    first = math.min(first, b.focus.row)
    while first < b.focus.row and not fits(first, b.focus.row) do
      first = first + 1
    end
  end
  local last = first
  while last < #lines and fits(first, last + 1) do
    last = last + 1
  end
  b.offset[ci] = first
  if first > 1 then
    table.insert(
      block,
      { chunks = M.fit_chunks({ { ("  %s %d more"):format(icons().up, first - 1), "LogposeBoardMore" } }, w) }
    )
  end
  for ri = first, last do
    for _, l in ipairs(lines[ri]) do
      table.insert(block, { chunks = l, card = ri })
    end
  end
  if last < #lines then
    table.insert(
      block,
      { chunks = M.fit_chunks({ { ("  %s %d more"):format(icons().down, #lines - last), "LogposeBoardMore" } }, w) }
    )
  end
  return block
end

--- Lane key of a card: its project ("" when it has none).
---@param it logpose.Item
---@return string
local function lane_of(it)
  return it.project or ""
end

--- Rows per project: column headers once, then for each project a divider and its cards in
--- each column. Called by `M.render` with its row builder.
---@param b logpose.Board
---@param add_row fun(segs: table[])
---@param today string
function M.render_lanes(b, add_row, today)
  local ic = icons()
  local headers = {}
  local lanes, seen = {}, {}
  for ci, col in ipairs(b.columns) do
    local block = column_block(b, ci, b.widths[ci], 0, today) -- just the header
    headers[ci] = { chunks = block[1].chunks, ci = ci }
    for _, it in ipairs(col.cards) do
      local lane = lane_of(it)
      if not seen[lane] then
        seen[lane] = true
        table.insert(lanes, lane)
      end
    end
  end
  table.sort(lanes, function(a, c)
    if (a == "") ~= (c == "") then
      return c == "" -- "no project" last
    end
    return a < c
  end)
  add_row(headers)
  local total = 0
  for ci = 1, #b.columns do
    total = total + b.widths[ci] + (ci > 1 and 1 or 0)
  end
  for _, lane in ipairs(lanes) do
    local label = " " .. ic.project .. " " .. (lane == "" and "no project" or lane) .. " "
    add_row({
      {
        chunks = M.fit_chunks({
          { ic.box.normal.h .. ic.box.normal.h, "LogposeBoardHint" },
          { label, "LogposeBoardProject" },
          { string.rep(ic.box.normal.h, math.max(total - vim.fn.strdisplaywidth(label) - 2, 0)), "LogposeBoardHint" },
        }, total),
      },
    })
    local blocks, rows = {}, 0
    for ci, col in ipairs(b.columns) do
      local block = {}
      if not b.collapsed[col.key] then
        for ri, it in ipairs(col.cards) do
          if lane_of(it) == lane then
            local focused = ci == b.focus.col and ri == b.focus.row
            for _, l in ipairs(M.card_lines(it, b.widths[ci], today, "LogposeBoardColumn" .. ci, focused, b.compact)) do
              table.insert(block, { chunks = l, card = ri })
            end
          end
        end
      end
      blocks[ci] = block
      rows = math.max(rows, #block)
    end
    for r = 1, rows do
      local segs = {}
      for ci, block in ipairs(blocks) do
        local seg = block[r] or { chunks = { { string.rep(" ", b.widths[ci]) } } }
        segs[ci] = { chunks = seg.chunks, card = seg.card, ci = ci }
      end
      add_row(segs)
    end
  end
end

--- Render into the board buffer and remember where each card is.
---@param b logpose.Board
---@param width integer window width
---@param height? integer window height (columns scroll within it)
function M.render(b, width, height)
  define_highlights()
  local today = date.today()
  local cfg = config.get().board
  local n = #b.columns
  local folded = 0
  for _, col in ipairs(b.columns) do
    if b.collapsed[col.key] then
      folded = folded + 1
    end
  end
  local open = math.max(n - folded, 1)
  local colw = math.floor((width - (n - 1) - folded * M.COLLAPSED_WIDTH) / open)
  b.stacked = colw < cfg.min_column_width
  b.width = b.stacked and math.max(width - 1, 12) or colw
  b.widths = {}
  for ci, col in ipairs(b.columns) do
    b.widths[ci] = (b.collapsed[col.key] and not b.stacked) and M.COLLAPSED_WIDTH or b.width
  end
  -- Rows for cards under each column header (the title is in the window's top bar). Stacked
  -- columns and rows per project don't scroll on their own: the buffer does.
  local avail = (b.stacked or b.lanes or not height) and math.huge or math.max(height - 1, 5)

  -- The window's top bar: title, scope, filter, modes, help.
  local scope = b.all and "all projects" or (b.project or "all projects")
  local modes = {}
  if b.lanes then
    table.insert(modes, "by project")
  end
  if b.compact then
    table.insert(modes, "compact")
  end
  b.title = "Board · " .. scope .. (b.filter ~= "" and (" · " .. b.filter) or "")
  if #modes > 0 then
    b.title = b.title .. " · " .. table.concat(modes, ", ")
  end
  local function esc(str)
    return (str:gsub("%%", "%%%%"))
  end
  local bar = "%#LogposeBoardTitle# Board%#LogposeBoardProject# · "
    .. esc(scope)
    .. (b.filter ~= "" and ("%#LogposeBoardHint# · " .. esc(b.filter)) or "")
    .. (#modes > 0 and ("%#LogposeBoardHint# · " .. table.concat(modes, ", ")) or "")
    .. "%=%#LogposeBoardHint#? help "
  local bar_win = vim.fn.bufwinid(b.buf)
  if bar_win ~= -1 then
    vim.wo[bar_win].winbar = bar
  end
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

  local blocks = {}
  for ci = 1, n do
    b.cards_at[ci] = {}
    blocks[ci] = column_block(b, ci, b.widths[ci], avail, today)
  end

  if b.lanes and not b.stacked then
    M.render_lanes(b, add_row, today)
  elseif b.stacked then
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
    local rows = 0
    for _, block in ipairs(blocks) do
      rows = math.max(rows, #block)
    end
    for r = 1, rows do
      local segs = {}
      for ci, block in ipairs(blocks) do
        local seg = block[r] or { chunks = { { string.rep(" ", b.widths[ci]) } } }
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

--- Window options that would eat columns, scroll sideways or draw over the board.
M.WINDOW_OPTIONS = {
  wrap = false,
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  statuscolumn = "",
  colorcolumn = "",
  list = false,
  spell = false,
  cursorcolumn = false,
  foldenable = false,
  sidescrolloff = 0,
}

--- Apply `M.WINDOW_OPTIONS` to a window showing the board.
---@param win integer
function M.setup_window(win)
  for opt, value in pairs(M.WINDOW_OPTIONS) do
    pcall(function()
      vim.wo[win][0][opt] = value
    end)
  end
end

--- Redraw at the size of the window showing the board: its text area, without any columns
--- the window still reserves (fold, sign, status), so nothing is cut off or scrolled sideways.
---@param b logpose.Board
local function redraw(b)
  local win = vim.fn.bufwinid(b.buf)
  if win == -1 then
    return -- not visible: drawn when it's shown again
  end
  local info = vim.fn.getwininfo(win)[1] or {}
  local width = vim.api.nvim_win_get_width(win) - (info.textoff or 0)
  M.render(b, width, vim.api.nvim_win_get_height(win))
  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    if view.leftcol ~= 0 then
      view.leftcol = 0
      vim.fn.winrestview(view)
    end
  end)
end

--- Redraw soon, once, however many resize events arrive (dragging, sidebars opening).
---@param b logpose.Board
local function redraw_soon(b)
  if b._pending then
    return
  end
  b._pending = true
  vim.defer_fn(function()
    b._pending = false
    if vim.api.nvim_buf_is_valid(b.buf) then
      redraw(b)
      if vim.api.nvim_get_current_buf() == b.buf then
        b._placing = true
        local win = vim.api.nvim_get_current_win()
        local pos = vim.api.nvim_win_get_cursor(win)
        local ci, ri = M.at(b, pos[1], pos[2])
        if not (ci == b.focus.col and ri == b.focus.row) then
          b._placing = false
          M._place_cursor(b)
        end
        b._placing = false
      end
    end
  end, 20)
end

--- Redraw so the focused card gets the heavy border (and is scrolled into view).
---@param b logpose.Board
function M.highlight_focus(b)
  redraw(b)
end

--- Put the cursor on the focused card (or the column header when it's empty).
---@param b logpose.Board
local function place_cursor(b)
  return M._place_cursor(b)
end

---@param b logpose.Board
function M._place_cursor(b)
  local win = vim.fn.bufwinid(b.buf)
  if win == -1 then
    return
  end
  local at = b.cards_at[b.focus.col] and b.cards_at[b.focus.col][b.focus.row]
  local row = at and (b.compact and at.first or at.first + 1) -- the title line, inside the box
  local inside = at and (b.compact and 0 or #(icons().box.normal.v .. " ")) or 0
  if not row then
    -- the column header
    for r, region in pairs(b.regions) do
      if b.stacked and region.stack_col == b.focus.col then
        row = row and math.min(row, r) or r
      end
    end
    row = row or 1
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
  if b.lanes then
    -- Group each column by project so j/k follow the cards as drawn.
    for _, col in ipairs(b.columns) do
      local pos = {}
      for i, it in ipairs(col.cards) do
        pos[it] = i
      end
      table.sort(col.cards, function(x, y)
        local lx, ly = lane_of(x), lane_of(y)
        if lx ~= ly then
          if (lx == "") ~= (ly == "") then
            return ly == ""
          end
          return lx < ly
        end
        return pos[x] < pos[y]
      end)
    end
  end
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
  redraw(b)
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
--- Contents of every live task file (path -> text), read from disk.
---@param b logpose.Board
---@return table<string, string>
local function snapshot(b)
  local fs = require("logpose.util.fs")
  local out = {}
  for _, t in ipairs(taskfile.list(b.root)) do
    out[t.path] = fs.read_file(t.path)
  end
  return out
end

--- Record what an action changed (compared with `before`) as one undo step.
---@param b logpose.Board
---@param label string
---@param before table<string, string>
local function record(b, label, before)
  local after = snapshot(b)
  local changes = {}
  for path, content in pairs(before) do
    if after[path] ~= content then
      table.insert(changes, { path = path, before = content, after = after[path] })
    end
  end
  for path, content in pairs(after) do
    if before[path] == nil then
      table.insert(changes, { path = path, before = nil, after = content })
    end
  end
  if #changes > 0 then
    table.insert(b.undo, { label = label, changes = changes })
    b.redo = {}
  end
end

--- Put each changed file back to `side` ("before" for undo, "after" for redo), if nothing
--- else changed it in between.
---@param b logpose.Board
---@param step { label: string, changes: table[] }
---@param side "before"|"after"
---@return boolean ok, string? path a file to focus
local function apply(b, step, side)
  local fs = require("logpose.util.fs")
  local other = side == "before" and "after" or "before"
  for _, c in ipairs(step.changes) do
    if fs.read_file(c.path) ~= c[other] then
      return false
    end
    local buf = fs.find_buf(c.path)
    if buf and vim.bo[buf].modified then
      return false
    end
  end
  local focus
  for _, c in ipairs(step.changes) do
    if c[side] == nil then
      os.remove(c.path)
      local buf = fs.find_buf(c.path)
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    else
      local ok, err = fs.write_file(c.path, c[side], { raw = true })
      if not ok then
        error(err, 0)
      end
      focus = focus or c.path
    end
  end
  require("logpose.index").clear_cache()
  return true, focus
end

--- `u`: take back the last change made on the board.
---@param b logpose.Board
function M.undo(b)
  local step = table.remove(b.undo)
  if not step then
    require("logpose.util.ui").notify("logpose: nothing to undo on the board", vim.log.levels.INFO)
    return
  end
  local ok, focus = apply(b, step, "before")
  if not ok then
    require("logpose.util.ui").notify(
      ("logpose: can't undo %s: the task changed since"):format(step.label),
      vim.log.levels.WARN
    )
    return
  end
  table.insert(b.redo, step)
  count(b, "undo")
  require("logpose.util.ui").notify(("logpose: undid %s"):format(step.label), vim.log.levels.INFO)
  M.refresh(b, focus)
end

--- `<C-r>`: redo what `u` took back.
---@param b logpose.Board
function M.redo(b)
  local step = table.remove(b.redo)
  if not step then
    require("logpose.util.ui").notify("logpose: nothing to redo on the board", vim.log.levels.INFO)
    return
  end
  local ok, focus = apply(b, step, "after")
  if not ok then
    require("logpose.util.ui").notify(
      ("logpose: can't redo %s: the task changed since"):format(step.label),
      vim.log.levels.WARN
    )
    return
  end
  table.insert(b.undo, step)
  count(b, "redo")
  require("logpose.util.ui").notify(("logpose: redid %s"):format(step.label), vim.log.levels.INFO)
  M.refresh(b, focus)
end

local function with_card(b, name, fn)
  local it = M.focused(b)
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  local before = snapshot(b)
  local ok, res = pcall(fn, it)
  record(b, name, before)
  if not ok then
    require("logpose.util.ui").notify(tostring(res), vim.log.levels.ERROR)
    return
  end
  if res == false then
    return
  end
  count(b, name)
  M.refresh(b, type(res) == "string" and res or it.file)
  if name == "move" or name == "done" then
    M.flash(b)
  end
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
  end, M.flash_ms)
end

--- How long a moved card stays highlighted.
M.flash_ms = 300

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
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
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
      local before = snapshot(b)
      local ok, err = os.remove(it.file)
      if not ok then
        error(("logpose: cannot delete %s: %s"):format(it.file, err), 0)
      end
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      require("logpose.index").clear_cache()
      record(b, "delete", before)
      count(b, "delete")
      require("logpose.util.ui").notify(("logpose: deleted %s"):format(vim.fs.basename(it.file)), vim.log.levels.INFO)
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
      local before = snapshot(b)
      local path = taskfile.create(b.root, { title = title, status = col.key, project = project })
      record(b, "add", before)
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

--- Fold the focused column to a narrow strip, or unfold it.
---@param b logpose.Board
function M.toggle_fold(b)
  local col = b.columns[b.focus.col]
  if not col then
    return
  end
  b.collapsed[col.key] = not b.collapsed[col.key] or nil
  M.highlight_focus(b)
  place_cursor(b)
end

--- The focused task in a floating window: the file itself, so you can read and edit it.
--- `q` or <Esc> closes it (saving changes) and the board picks them up.
---@param b logpose.Board
---@return integer? win
function M.peek(b)
  local it = M.focused(b)
  if not it then
    require("logpose.util.ui").notify("logpose: no card here", vim.log.levels.INFO)
    return
  end
  count(b, "peek")
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
    title = " " .. M.fit(it.text, width - 4):gsub("%s+$", "") .. " ",
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
          M.refresh(b, it.file)
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
      M.refresh(b)
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
  map("<C-j>", function()
    M.reorder(b, 1)
  end, "Move card down")
  map("<C-k>", function()
    M.reorder(b, -1)
  end, "Move card up")
  map("K", function()
    M.peek(b)
  end, "Peek at the task")
  map("z", function()
    M.toggle_fold(b)
  end, "Fold / unfold the column")
  map("c", function()
    b.compact = not b.compact
    M.refresh(b, (M.focused(b) or {}).file)
  end, "Compact cards on / off")
  map("s", function()
    b.lanes = not b.lanes
    M.refresh(b, (M.focused(b) or {}).file)
  end, "Rows per project on / off")
  map("gg", function()
    b.focus.row = 1
    M.highlight_focus(b)
    place_cursor(b)
  end, "First card")
  map("G", function()
    b.focus.row = #b.columns[b.focus.col].cards
    clamp(b)
    M.highlight_focus(b)
    place_cursor(b)
  end, "Last card")
  map("a", function()
    M.add(b)
  end, "Add card")
  map("D", function()
    M.delete(b)
  end, "Delete card")
  map("u", function()
    M.undo(b)
  end, "Undo the last board change")
  map("<C-r>", function()
    M.redo(b)
  end, "Redo")
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
    require("logpose.util.ui").notify(table.concat(M.HELP, "\n"), vim.log.levels.INFO)
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
  local tab
  if config.get().board.open == "tab" then
    vim.cmd("tabnew")
    tab = vim.api.nvim_get_current_tabpage()
    local scratch = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(0, buf)
    if scratch ~= buf and vim.api.nvim_buf_get_name(scratch) == "" then
      pcall(vim.api.nvim_buf_delete, scratch, { force = true })
    end
  else
    vim.api.nvim_win_set_buf(0, buf)
  end
  M.setup_window(vim.api.nvim_get_current_win())
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
    collapsed = {},
  }
  for _, key in ipairs(config.get().board.collapsed) do
    b.collapsed[key] = true
  end
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
  -- Coming back to the board: reload (files may have changed) and redraw.
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
        M.refresh(b, (M.focused(b) or {}).file)
      end
    end,
  })
  -- Any window that starts showing the board gets the board's window options.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function()
      M.setup_window(vim.api.nvim_get_current_win())
      redraw_soon(b)
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
        redraw_soon(b)
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

--- Board layout and drawing: columns (scrolling, folded, stacked, rows per project), the top
--- bar, where each card is, the cursor, and refreshing from disk.
local config = require("logpose.config")
local date = require("logpose.util.date")
local text = require("logpose.board.text")
local cards = require("logpose.board.cards")
local collect = require("logpose.board.collect")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.board")

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
      chunks = text.fit_chunks({
        { cards.icons().folded, col_hl },
        { tostring(#col.cards), over and "LogposeBoardOverLimit" or "LogposeBoardHint" },
      }, w),
    })
    -- The label, one letter per line.
    local n = vim.fn.strchars(col.label)
    for i = 0, math.min(n, avail) - 1 do
      table.insert(block, { chunks = text.fit_chunks({ { " " .. vim.fn.strcharpart(col.label, i, 1), col_hl } }, w) })
    end
    return block
  end
  local count = limit and ("(%d/%d)"):format(#col.cards, limit) or ("(%d)"):format(#col.cards)
  table.insert(block, {
    chunks = text.fit_chunks({
      { cards.icons().column .. " ", col_hl },
      { col.label .. " ", col_hl },
      { count, over and "LogposeBoardOverLimit" or "LogposeBoardHint" },
    }, w),
  })
  if #col.cards == 0 then
    table.insert(block, { chunks = text.fit_chunks({ { "  " .. cards.icons().empty, "LogposeBoardEmpty" } }, w) })
    return block
  end
  local lines = {}
  for ri, it in ipairs(col.cards) do
    lines[ri] = cards.card_lines(it, w, today, {
      col_hl = col_hl,
      focused = ci == b.focus.col and ri == b.focus.row,
      compact = b.compact,
      marked = b.marked[it.file],
      -- on a one-project board the project is on every card: say it once, in the bar
      show_project = b.all or not b.project,
    })
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
      { chunks = text.fit_chunks({ { ("  %s %d more"):format(cards.icons().up, first - 1), "LogposeBoardMore" } }, w) }
    )
  end
  for ri = first, last do
    for _, l in ipairs(lines[ri]) do
      table.insert(block, { chunks = l, card = ri })
    end
  end
  if last < #lines then
    table.insert(block, {
      chunks = text.fit_chunks(
        { { ("  %s %d more"):format(cards.icons().down, #lines - last), "LogposeBoardMore" } },
        w
      ),
    })
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
  local ic = cards.icons()
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
    local divider = add_row({
      {
        chunks = text.fit_chunks({
          { ic.box.normal.h .. ic.box.normal.h, "LogposeBoardHint" },
          { label, lane ~= "" and cards.project_group(lane) or "LogposeBoardProject" },
          { string.rep(ic.box.normal.h, math.max(total - vim.fn.strdisplaywidth(label) - 2, 0)), "LogposeBoardHint" },
        }, total),
      },
    })
    b.lane_rows[divider] = lane
    local blocks, rows = {}, 0
    for ci, col in ipairs(b.columns) do
      local block = {}
      if not b.collapsed[col.key] then
        for ri, it in ipairs(col.cards) do
          if lane_of(it) == lane then
            local focused = ci == b.focus.col and ri == b.focus.row
            for _, l in
              ipairs(cards.card_lines(it, b.widths[ci], today, {
                col_hl = "LogposeBoardColumn" .. ci,
                focused = focused,
                compact = b.compact,
                marked = b.marked[it.file],
                show_project = false, -- the row says which project
              }))
            do
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
      b.lane_rows[add_row(segs)] = lane
    end
  end
end

--- The project row (lane) under the cursor when cards are grouped by project: a project name,
--- "" for the "no project" row, or nil when not in that mode.
---@param b logpose.Board
---@return string?
function M.lane_at_cursor(b)
  if not b.lanes or b.stacked or not b.lane_rows then
    return nil
  end
  local win = vim.fn.bufwinid(b.buf)
  local row = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or nil
  local lane = row and b.lane_rows[row]
  if lane == nil then
    local it = M.focused(b)
    lane = it and (it.project or "") or nil
  end
  return lane
end

--- Render into the board buffer and remember where each card is.
---@param b logpose.Board
---@param width integer window width
---@param height? integer window height (columns scroll within it)
function M.render(b, width, height)
  cards.define_highlights()
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
  local colw = math.floor((width - (n - 1) - folded * cards.COLLAPSED_WIDTH) / open)
  b.stacked = colw < cfg.min_column_width
  b.width = b.stacked and math.max(width - 1, 12) or colw
  b.widths = {}
  for ci, col in ipairs(b.columns) do
    b.widths[ci] = (b.collapsed[col.key] and not b.stacked) and cards.COLLAPSED_WIDTH or b.width
  end
  -- Rows for cards under each column header (the title is in the window's top bar). Stacked
  -- columns and rows per project don't scroll on their own: the buffer does.
  local avail = (b.stacked or b.lanes or not height) and math.huge or math.max(height - 1, 5)

  -- Marks only cover cards on the board (a filter or the project scope drops the others).
  local visible, marked = {}, 0
  for _, col in ipairs(b.columns) do
    for _, it in ipairs(col.cards) do
      visible[it.file] = true
    end
  end
  for file in pairs(b.marked) do
    if visible[file] then
      marked = marked + 1
    else
      b.marked[file] = nil
    end
  end

  -- The window's top bar: title, scope, filter, modes, help.
  local scope = b.all and "all projects" or (b.project or "all projects")
  local modes = {}
  if marked > 0 then
    table.insert(modes, ("%d marked"):format(marked))
  end
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
  b.segments, b.regions, b.cards_at, b.lane_rows = {}, {}, {}, {}

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
    return row
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
  -- The focused card gets a background (under its colours), so it reads as selected anywhere.
  local at = b.cards_at[b.focus.col] and b.cards_at[b.focus.col][b.focus.row]
  if at then
    -- A boxed card: only inside its border, or the border cells' background frames it twice.
    local boxed = at.last > at.first
    for row = boxed and at.first + 1 or at.first, boxed and at.last - 1 or at.last do
      local starts = b.segments[row] or {}
      local start = b.stacked and 0 or starts[b.focus.col]
      local len = #(lines[row] or "")
      local stop = math.min((not b.stacked and starts[b.focus.col + 1]) and (starts[b.focus.col + 1] - 1) or len, len)
      local seg = start and start < len and lines[row]:sub(start + 1, stop):match("^(.-)%s*$") or ""
      if boxed then
        -- the edge glyphs, left (`┃`, or a blocked card's red edge) and right
        start, stop = start and start + #seg:match("^%S*"), (start or 0) + #seg - #seg:match("%S*$")
      end
      -- only the card's own rows, not the gap below it
      if seg:match("%S") and start < stop then
        pcall(vim.api.nvim_buf_set_extmark, b.buf, ns, row - 1, start, {
          end_col = stop,
          hl_group = "LogposeBoardFocusBg",
          priority = 100,
        })
      end
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
function M.clamp(b)
  b.focus.col = math.max(1, math.min(b.focus.col, #b.columns))
  local count = #b.columns[b.focus.col].cards
  b.focus.row = math.max(1, math.min(b.focus.row, math.max(count, 1)))
end

--- Window options that would eat columns, scroll sideways or draw over the board.
M.WINDOW_OPTIONS = {
  wrap = false,
  -- the focused card has its own background; a cursorline would draw a band across the board
  cursorline = false,
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
function M.redraw_soon(b)
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
function M.place_cursor(b)
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
  local inside = at and (b.compact and 0 or #(cards.icons().box.normal.v .. " ")) or 0
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
  local project = require("logpose.project")
  local pages = project.pages(b.root)
  cards.project_hl = {}
  for name in pairs(pages) do
    cards.project_hl[name] = project.hl(b.root, name, pages)
  end
  local scoped = (not b.all) and b.project or nil
  b.columns = collect.collect(b.root, {
    project = scoped,
    filter = b.filter,
    -- archived projects stay out of the all-projects view
    hidden = not scoped and require("logpose.project").archived(b.root) or nil,
  })
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
  M.clamp(b)
  redraw(b)
  M.place_cursor(b)
end

return M

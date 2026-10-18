--- How a card looks: highlight groups, glyph sets, project colours, and one card as box lines
--- (or one compact line).
local config = require("logpose.config")
local date = require("logpose.util.date")
local text = require("logpose.board.text")

local M = {}

--- Highlight group per project with a `color:` in its project page (set on refresh).
---@type table<string, string>
M.project_hl = {}

--- A project's colour mixed with the background: for card borders, coloured but quieter than
--- the text. Without true colours, the project's colour itself.
---@param name string
---@return string
function M.project_border(name)
  local source = M.project_group(name)
  local group = "LogposeProjectBorder_" .. name:gsub("[^%w]", "_")
  local fg = vim.api.nvim_get_hl(0, { name = source, link = false }).fg
  if not (vim.o.termguicolors and fg) then
    vim.api.nvim_set_hl(0, group, { link = source })
    return group
  end
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or (vim.o.background == "light" and 0xffffff or 0x000000)
  local function mix(shift)
    local a, b = math.floor(fg / shift) % 256, math.floor(bg / shift) % 256
    return math.floor(a * 0.6 + b * 0.4 + 0.5)
  end
  vim.api.nvim_set_hl(0, group, { fg = mix(65536) * 65536 + mix(256) * 256 + mix(1) })
  return group
end

--- A project's colour: its page's `color:`, else an automatic one from the colour scheme.
---@param name string
---@return string
function M.project_group(name)
  return M.project_hl[name] or require("logpose.project").auto_hl(name) or "LogposeBoardProject"
end

--- Highlight groups, linked to standard groups so colour schemes style them; override any with
--- `vim.api.nvim_set_hl(0, "LogposeBoard…", {...})`.
M.HL = {
  LogposeBoardTitle = "Title",
  LogposeBoardHint = "Comment",
  LogposeBoardFocus = false, -- Normal's text colour, without its background (see below)
  LogposeBoardFocusTitle = { bold = true },
  LogposeBoardProject = "Identifier",
  LogposeBoardTag = "Comment",
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
  LogposeBoardMarked = "DiagnosticOk",
  LogposeBoardBorder = "Comment",
  LogposeBoardDoneBorder = "NonText",
  LogposeBoardDone = "Comment",
  LogposeBoardMeta = "Comment",
  LogposeBoardDueSoon = "DiagnosticWarn",
  LogposeBoardFocusBg = "CursorLine",
}
--- Column colours by position (a column's `hl` overrides): grey, blue, yellow, purple, green.
M.COLUMN_HL = { "Comment", "DiagnosticInfo", "DiagnosticWarn", "DiagnosticHint", "DiagnosticOk" }

--- Width of a folded column.
M.COLLAPSED_WIDTH = 5

function M.define_highlights()
  -- The focused card's border: the plain text colour (no column's colour), bold. Normal's
  -- background would hide the focused card's own.
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "LogposeBoardFocus", { fg = normal.fg, bold = true, default = true })
  for name, link in pairs(M.HL) do
    if link then
      local spec = type(link) == "table" and vim.tbl_extend("force", { default = true }, link)
        or { link = link, default = true }
      vim.api.nvim_set_hl(0, name, spec)
    end
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
    marked = "✓",
    done = "✓",
    edge = "┃",
    sep = " · ",
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
    marked = "✓",
    done = "✓",
    edge = "┃",
    sep = " · ",
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
    marked = "x",
    done = "v",
    edge = "|",
    sep = "  ",
    empty = "- empty -",
    box = {
      normal = { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|" },
      focus = { tl = "#", tr = "#", bl = "#", br = "#", h = "=", v = "#" },
    },
  },
}

---@return table
function M.icons()
  return M.ICONS[config.get().board.icons] or M.ICONS.unicode
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

--- When a task is due, in words, and how it should look: overdue (red), due today or
--- tomorrow (yellow), this week (the weekday) or later (the date), both muted. Done tasks: nil.
---@param it logpose.Item
---@param today string
---@return string?, string?
function M.due_text(it, today)
  if not it.due or not date.is_iso(it.due) or it.status == config.get().board.done then
    return nil
  end
  local d = date.diff_days(today, it.due)
  if d < 0 then
    return ("overdue %dd"):format(-d), "LogposeBoardOverdue"
  elseif d == 0 then
    return "due today", "LogposeBoardDueSoon"
  elseif d == 1 then
    return "due tomorrow", "LogposeBoardDueSoon"
  elseif d < 7 then
    return "due " .. date.weekday_name(it.due):sub(1, 3), "LogposeBoardDue"
  end
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  local _, m, day = it.due:match("^(%d+)-(%d+)-(%d+)$")
  return ("due %d %s"):format(tonumber(day), months[tonumber(m)]), "LogposeBoardDue"
end

--- The card's state, which decides how it looks.
---@param it logpose.Item
---@param today string
---@return { done: boolean, blocked: boolean, stale: boolean, idle?: integer }
function M.state(it, today)
  local done = it.status == config.get().board.done
  local age = M.age(it, today)
  local stale = not done and age ~= nil and age >= config.get().board.stale_days
  return { done = done, blocked = it.blocked ~= nil, stale = stale, idle = stale and age or nil }
end

--- The details under the title, quietly: project (with its colour mark), when it's due, how long
--- it has sat untouched (only once that's worth noticing), tags. They're fitted by importance,
--- not cut at the end: dates always, then the project (shortened if need be), then whole tags.
---@param it logpose.Item
---@param today string
---@param show_project boolean
---@param width? integer  cells available (default: no limit)
---@return logpose.Chunk[]
function M.details(it, today, show_project, width)
  local ic = M.icons()
  local st = M.state(it, today)
  local w = vim.fn.strdisplaywidth
  local sep_w = w(ic.sep)
  local room = width or math.huge
  local due, due_hl = M.due_text(it, today)
  local dates = {}
  if due then
    table.insert(dates, { due, due_hl })
  end
  if st.idle then
    table.insert(dates, { ("idle %dd"):format(st.idle), "LogposeBoardStale" })
  end
  local used = 0
  for i, d in ipairs(dates) do
    used = used + w(d[1]) + (i > 1 and sep_w or 0)
  end
  -- the project, before the dates, in whatever room they leave
  local project
  if show_project and it.project then
    local mark = ic.project .. " "
    local avail = room - used - (used > 0 and sep_w or 0) - w(mark)
    local name = it.project
    if w(name) > avail then
      -- a stub like "th…" says nothing: below a few letters, the colour mark alone
      name = avail >= 6 and text.fit(name, avail):gsub("%s+$", "") or ""
    end
    local mark_hl = M.project_group(it.project)
    if name ~= "" then
      -- the project in its colour: which project a card belongs to is worth colour
      project = { { mark, mark_hl }, { name, mark_hl } }
      used = used + w(mark) + w(name) + (used > 0 and sep_w or 0)
    elseif room - used - (used > 0 and sep_w or 0) >= w(ic.project) then
      project = { { ic.project, mark_hl } }
      used = used + w(ic.project) + (used > 0 and sep_w or 0)
    end
  end
  -- tags last, only whole ones
  local tags = {}
  for _, t in ipairs(it.tags or {}) do
    if t ~= it.project then
      local tw = w("#" .. t) + ((used > 0) and sep_w or 0)
      if used + tw <= room then
        table.insert(tags, { "#" .. t, "LogposeBoardTag" })
        used = used + tw
      end
    end
  end
  local out = {}
  local function add(chunks)
    if #out > 0 then
      -- a lone colour mark is followed by a space, not a separator
      table.insert(out, { (project and #project == 1 and #out == 1) and " " or ic.sep, "LogposeBoardMeta" })
    end
    vim.list_extend(out, chunks)
  end
  if project then
    add(project)
  end
  for _, d in ipairs(dates) do
    add({ d })
  end
  for _, t in ipairs(tags) do
    add({ t })
  end
  return out
end

---@class logpose.CardOpts
---@field col_hl string       the column's highlight group (borders, with `board.border = "column"`)
---@field focused? boolean
---@field compact? boolean    one line, no box
---@field marked? boolean
---@field show_project? boolean  false when the board shows one project, or rows per project

--- One card as box lines of `w` cells. Each line is a list of chunks.
---
--- Colour only where it means something: borders are neutral, the focused card has a heavy
--- border (and a background, from the view), a blocked card a red left edge and reason, a
--- marked card a check on its top border. Done cards are dimmed with a ✓, untouched ones faded.
---@param it logpose.Item
---@param w integer
---@param today string
---@param o logpose.CardOpts
---@return logpose.Chunk[][]
function M.card_lines(it, w, today, o)
  local ic = M.icons()
  if o.compact then
    return { M.compact_line(it, w, today, o) }
  end
  local st = M.state(it, today)
  local box = o.focused and ic.box.focus or ic.box.normal
  local style = config.get().board.border
  local border = o.focused and "LogposeBoardFocus"
    or (o.marked and "LogposeBoardMarked")
    or (style == "column" and (st.blocked and "LogposeBoardBlocked" or o.col_hl))
    or (st.done and "LogposeBoardDoneBorder")
    or (style == "project" and it.project and M.project_border(it.project))
    or "LogposeBoardBorder"
  -- a blocked card's left edge is red whatever else its border shows
  local left = st.blocked and { ic.edge .. " ", "LogposeBoardBlocked" } or { box.v .. " ", border }
  local inner = math.max(w - 4, 1)
  local out = {}
  local function row(chunks)
    local line = { left }
    vim.list_extend(line, text.fit_chunks(chunks, inner))
    table.insert(line, { " " .. box.v, border })
    table.insert(out, line)
  end
  if o.marked and w >= 8 then
    -- a check on the top border: ╭─ ✓ ───╮
    local chip = " " .. ic.marked .. " "
    local rest = math.max(w - 3 - vim.fn.strdisplaywidth(chip), 0)
    table.insert(out, {
      { box.tl .. box.h, border },
      { chip, "LogposeBoardMarked" },
      { string.rep(box.h, rest) .. box.tr, border },
    })
  else
    table.insert(out, { { box.tl .. string.rep(box.h, w - 2) .. box.tr, border } })
  end
  local title_hl = (o.focused and "LogposeBoardFocusTitle")
    or (st.done and "LogposeBoardDone")
    or ((st.stale and not st.blocked) and "LogposeBoardFaded")
    or nil
  local title = st.done and (ic.done .. " " .. it.text) or it.text
  for _, l in ipairs(text.wrap(title, inner, 2)) do
    row({ { l, title_hl } })
  end
  if st.blocked then
    row({ { ic.blocked .. " " .. (it.blocked == "yes" and "blocked" or it.blocked), "LogposeBoardBlocked" } })
  end
  local details = M.details(it, today, o.show_project ~= false, inner)
  if #details > 0 then
    row(details)
  end
  table.insert(out, { { box.bl .. string.rep(box.h, w - 2) .. box.br, border } })
  return out
end

--- A card on one line: a marker (▶ focused, ✓ marked, ⊘ blocked, ✓ done), the title, then
--- when it's due and how long it has sat untouched, at the end.
---@param it logpose.Item
---@param w integer
---@param today string
---@param o logpose.CardOpts
---@return logpose.Chunk[]
function M.compact_line(it, w, today, o)
  local ic = M.icons()
  local st = M.state(it, today)
  local marker, marker_hl = ic.card, "LogposeBoardBorder"
  if st.done then
    marker, marker_hl = ic.done, "LogposeBoardDone"
  end
  if st.blocked then
    marker, marker_hl = ic.blocked, "LogposeBoardBlocked"
  end
  if o.marked then
    marker, marker_hl = ic.marked, "LogposeBoardMarked"
  end
  if o.focused then
    marker, marker_hl = ic.focus, "LogposeBoardFocus"
  end
  local tail = {}
  local due, due_hl = M.due_text(it, today)
  if due then
    table.insert(tail, { " " .. due, due_hl })
  end
  if st.idle then
    table.insert(tail, { (" idle %dd"):format(st.idle), "LogposeBoardStale" })
  end
  local tail_w = 0
  for _, c in ipairs(tail) do
    tail_w = tail_w + vim.fn.strdisplaywidth(c[1])
  end
  local title_w = math.max(w - 2 - tail_w, 1)
  local title_hl = (o.focused and "LogposeBoardFocusTitle")
    or (st.done and "LogposeBoardDone")
    or ((st.stale and not st.blocked) and "LogposeBoardFaded")
    or nil
  local line = { { marker .. " ", marker_hl }, { text.fit(it.text, title_w), title_hl } }
  vim.list_extend(line, tail)
  return text.fit_chunks(line, w)
end

return M

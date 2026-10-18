--- How a card looks: highlight groups, glyph sets, project colours, and one card as box lines
--- (or one compact line).
local config = require("logpose.config")
local date = require("logpose.util.date")
local text = require("logpose.board.text")

local M = {}

--- Highlight group per project with a `color:` in its project page (set on refresh).
---@type table<string, string>
M.project_hl = {}

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
  LogposeBoardMarked = "DiagnosticOk",
}
--- Column colours by position (a column's `hl` overrides): grey, blue, yellow, purple, green.
M.COLUMN_HL = { "Comment", "DiagnosticInfo", "DiagnosticWarn", "DiagnosticHint", "DiagnosticOk" }

--- Width of a folded column.
M.COLLAPSED_WIDTH = 5

function M.define_highlights()
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
    marked = "✓",
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

--- One card as box lines of `w` cells. Each line is a list of chunks.
---@param it logpose.Item
---@param w integer
---@param today string
---@param col_hl string the column's highlight group
---@param focused boolean
---@param compact? boolean one line, no box
---@return logpose.Chunk[][]
function M.card_lines(it, w, today, col_hl, focused, compact, marked)
  local ic = M.icons()
  if compact then
    return { M.compact_line(it, w, today, col_hl, focused, marked) }
  end
  local box = focused and ic.box.focus or ic.box.normal
  local border = focused and "LogposeBoardFocus"
    or (marked and "LogposeBoardMarked")
    or (it.blocked and "LogposeBoardBlocked" or col_hl)
  local inner = math.max(w - 4, 1)
  local age = M.age(it, today)
  local stale = age and age >= config.get().board.stale_days
  local out = {}
  local function row(chunks)
    local line = { { box.v .. " ", border } }
    vim.list_extend(line, text.fit_chunks(chunks, inner))
    table.insert(line, { " " .. box.v, border })
    table.insert(out, line)
  end
  if marked and w >= 8 then
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
  local title_hl = focused and "LogposeBoardFocusTitle" or (stale and "LogposeBoardFaded" or nil)
  for _, l in ipairs(text.wrap(it.text, inner, 2)) do
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
    add(ic.project .. " " .. it.project, M.project_hl[it.project] or "LogposeBoardProject")
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
function M.compact_line(it, w, today, col_hl, focused, marked)
  local ic = M.icons()
  local marker, marker_hl = ic.card, col_hl
  if it.blocked then
    marker, marker_hl = ic.blocked, "LogposeBoardBlocked"
  end
  if marked then
    marker, marker_hl = ic.marked, "LogposeBoardMarked"
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
  local line = { { marker .. " ", marker_hl }, { text.fit(it.text, title_w), title_hl } }
  vim.list_extend(line, tail)
  return text.fit_chunks(line, w)
end

return M

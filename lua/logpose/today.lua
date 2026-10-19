--- `:Logpose today`: the day at a glance, in two parts. Tasks: what's in progress, blocked and
--- due soon. Notes: today's meetings, the to-dos left in today's daily note, overdue action items
--- and the notes edited lately. <CR> opens an item.
local config = require("logpose.config")
local date = require("logpose.util.date")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.today")

---@class logpose.TodayLine
---@field text string
---@field hl? string
---@field file? string
---@field lnum? integer

--- How many notes "Recently edited" lists, edited within how many days.
M.RECENT = 5
M.RECENT_DAYS = 7

--- The sections, as lines.
---@param root string
---@param today string
---@return logpose.TodayLine[]
function M.build(root, today)
  local cfg = config.get()
  local items = require("logpose.index").build(root)
  local lines = {} ---@type logpose.TodayLine[]
  local function add(text, extra)
    table.insert(lines, vim.tbl_extend("force", { text = text }, extra or {}))
  end
  local function part(title)
    add("")
    add("## " .. title, { hl = "Title" })
  end
  local function section(title, entries)
    add("")
    add(("### %s (%d)"):format(title, #entries), { hl = "Title" })
    add("")
    if #entries == 0 then
      add("  nothing", { hl = "Comment" })
    end
    for _, e in ipairs(entries) do
      add(e.text, e)
    end
  end
  local function proj(it)
    return it.project and ("  ◆ " .. it.project) or ""
  end

  -- Header: the day and where it sits in the sprint or week.
  local head = ("# Today · %s %s"):format(date.weekday_name(today), today)
  local ok, p = pcall(require("logpose.period").of, today)
  if ok and p then
    local n, total = require("logpose.statusline").workday(p, today)
    head = head .. ("  ·  %s, day %d of %d"):format(p.kind == "sprint" and p.key or "week", n, total)
  end
  add(head, { hl = "Title" })

  local meetings, doing, blocked, due = {}, {}, {}, {}
  for _, it in ipairs(items) do
    if it.kind == "note" and it.file_type == "meeting" and it.date == today then
      table.insert(meetings, { text = "- " .. it.text .. proj(it), file = it.file, lnum = 1 })
    elseif it.kind == "task" and not it.archived and it.status ~= cfg.board.done then
      local entry = { file = it.file, lnum = 1 }
      if it.status == cfg.board.start then
        table.insert(doing, vim.tbl_extend("force", entry, { text = "- " .. it.text .. proj(it) }))
      end
      if it.blocked then
        local reason = it.blocked == "yes" and "" or (": " .. it.blocked)
        table.insert(blocked, vim.tbl_extend("force", entry, { text = "- " .. it.text .. reason .. proj(it) }))
      end
      if it.due and date.diff_days(today, it.due) <= 3 then
        local w, urgency = date.due(it.due, today)
        table.insert(
          due,
          vim.tbl_extend("force", entry, {
            text = ("- %s  (%s)%s"):format(it.text, w, proj(it)),
            hl = urgency == "overdue" and "DiagnosticError" or nil,
            due = it.due,
          })
        )
      end
    end
  end
  table.sort(due, function(a, b)
    return a.due < b.due
  end)
  local overdue = vim.tbl_map(function(it)
    return {
      text = ("- %s  (%s)%s"):format((it.text:gsub("%s*due:%S+", "")), (date.due(it.due, today)), proj(it)),
      file = it.file,
      lnum = it.lnum,
    }
  end, require("logpose.actions").collect(root, "overdue", {}, today))

  -- What's left in today's daily note.
  local daily = require("logpose.notes.daily").path(today, root)
  local left = {}
  local fs = require("logpose.util.fs")
  local buf = fs.find_buf(daily)
  local dlines = buf and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or fs.read_lines(daily)
  if dlines then
    local first, last = require("logpose.standup").section_range(dlines, cfg.standup.sections.today)
    for lnum = first or 1, first and last or 0 do
      local t = require("logpose.todos").parse(dlines[lnum])
      if t and not t.checked and vim.trim(t.text) ~= "" then
        table.insert(left, { text = "- [ ] " .. t.text, file = daily, lnum = lnum })
      end
    end
  end

  -- Notes edited lately (not tasks: they're on the board), so a note is easy to get back to.
  local recent = {}
  local now = os.time()
  local daily_n = fs.normalize(daily)
  -- project pages stay out: logpose itself writes them (colours, archiving)
  local kinds = { daily = true, meeting = true, topic = true, other = true }
  for _, it in ipairs(items) do
    if
      it.kind == "note"
      and kinds[it.file_type]
      and it.mtime
      and now - it.mtime < M.RECENT_DAYS * 86400
      and it.file ~= daily_n
    then
      table.insert(recent, it)
    end
  end
  table.sort(recent, function(a, b)
    if a.mtime ~= b.mtime then
      return a.mtime > b.mtime
    end
    return a.title < b.title
  end)
  local edited = {}
  for i = 1, math.min(M.RECENT, #recent) do
    local it = recent[i]
    table.insert(edited, {
      text = ("- %s  (%s)%s"):format(it.title, date.ago(it.mtime, now), proj(it)),
      file = it.file,
      lnum = 1,
    })
  end

  -- Tasks (the board) and notes (with the to-dos in them) are kept apart.
  part("Tasks")
  section(require("logpose.taskfile").label(cfg.board.start), doing)
  section("Blocked", blocked)
  section("Due soon", due)
  part("Notes")
  section("Meetings today", meetings)
  section("To-dos left in today's note", left)
  section("Overdue action items", overdue)
  section("Recently edited", edited)
  add("")
  add("<CR> open · d daily note · b board · r refresh · q close", { hl = "Comment" })
  return lines
end

---@param buf integer
---@param root string
local function render(buf, root)
  local lines = M.build(root, date.today())
  vim.b[buf].logpose_today = vim.tbl_map(function(l)
    return l.file and { file = l.file, lnum = l.lnum } or false
  end, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(l)
      return l.text
    end, lines)
  )
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, l in ipairs(lines) do
    if l.hl and l.text ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #l.text, hl_group = l.hl })
    end
  end
end

---@param root string
---@return integer buf
function M.open(root)
  local name = "logpose://today"
  local existing = vim.fn.bufnr(name)
  if existing > 0 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_win_set_buf(0, buf)
  render(buf, root)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", function()
    local loc = (vim.b[buf].logpose_today or {})[vim.api.nvim_win_get_cursor(0)[1]]
    if loc then
      vim.cmd.edit(vim.fn.fnameescape(loc.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { loc.lnum, 0 })
    end
  end, "Open")
  map("r", function()
    render(buf, root)
  end, "Refresh")
  map("d", function()
    vim.cmd("Logpose daily")
  end, "Daily note")
  map("b", function()
    vim.cmd("Logpose board")
  end, "Board")
  map("q", function()
    local alt = vim.fn.bufnr("#")
    if alt > 0 and alt ~= buf and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
      vim.cmd.buffer(alt)
    else
      vim.cmd.enew()
    end
  end, "Close")
  return buf
end

---@param _ logpose.CommandOpts
function M.command(_)
  config.with_root(ui.safely(function(root)
    M.open(root)
  end))
end

return M

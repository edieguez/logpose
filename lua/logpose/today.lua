--- `:Logpose today`: the day at a glance: tasks due soon (or overdue), overdue action items,
--- notes edited lately. Your status lives in the daily note (`notes/status.lua`): `d` opens it,
--- `y` copies it. <CR> opens an item.
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

  -- Due in the next few days, or overdue.
  local due = {}
  for _, it in ipairs(items) do
    if it.kind == "task" and not it.archived and not require("logpose.taskfile").is_closed(it.status) and it.due then
      local days = date.diff_days(today, it.due)
      if days <= 3 then
        local w = date.due(it.due, today)
        table.insert(
          due,
          { text = ("- %s  (%s)%s"):format(it.text, w, proj(it)), file = it.file, lnum = 1, due = it.due }
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
  local fs = require("logpose.util.fs")
  local daily = require("logpose.notes.daily").path(today, root)

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

  part("Coming up")
  section("Due soon", due)
  section("Overdue action items", overdue)
  section("Recently edited", edited)
  add("")
  add(
    "<CR> open · d daily note (your status) · y copy the status · b board · r refresh · q close",
    { hl = "Comment" }
  )
  return lines
end

---@param buf integer
---@param root string
local function render(buf, root)
  local lines = M.build(root, date.today())
  vim.b[buf].logpose_today = vim.tbl_map(function(l)
    return l.file and { file = l.file, lnum = l.lnum } or false
  end, lines)
  require("logpose.util.screen").draw(
    buf,
    ns,
    vim.tbl_map(function(l)
      return { { l.text, l.hl } }
    end, lines)
  )
end

---@param root string
---@return integer buf
function M.open(root)
  local buf = ui.screen_buf("logpose://today", "markdown")
  require("logpose.util.screen").window(buf, require("logpose.util.ui").show(buf))
  render(buf, root)
  local map = ui.mapper(buf)
  map(
    "y",
    ui.safely(function()
      require("logpose.notes.daily").copy(root)
    end),
    "Copy the status (daily note)"
  )
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
    require("logpose.util.screen").leave(buf)
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

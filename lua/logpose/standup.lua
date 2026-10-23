--- The standup, worked out from what happened, not from sections you fill in:
---   Yesterday  tasks you moved or finished (from their logs), meetings you had, to-dos checked
---              in your daily notes, since the previous workday
---   Today      tasks in progress or due, today's meetings, the open to-dos in today's daily
---              note (or the ones it will carry over)
---   Blockers   blocked tasks with their reasons, and lines under a `## Blockers` heading in the
---              daily note
--- The today screen shows it at the top (`y` copies it); `:Logpose standup` opens it there,
--- `:Logpose standup!` copies it, `:Logpose standup DATE` shows another day's.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

---@class logpose.StandupItem
---@field text string
---@field note? string     what happened ("TODO → Done", "meeting", "to-do")
---@field project? string
---@field file? string
---@field lnum? integer
---@field done? boolean    finished: shown checked

---@class logpose.Standup
---@field date string
---@field since string     the previous workday: Yesterday covers since .. date - 1
---@field yesterday logpose.StandupItem[]
---@field today logpose.StandupItem[]
---@field blockers logpose.StandupItem[]

--- Status moves in a task's `## Log` between `from` and `to` (inclusive), oldest first.
---@param lines string[]
---@param from string
---@param to string
---@return { from?: string, to: string }[]
local function moves(lines, from, to)
  local out, in_log = {}, false
  for _, l in ipairs(lines) do
    if l:match("^##%s+[Ll]og%s*$") then
      in_log = true
    elseif l:match("^#+%s") then
      in_log = false
    elseif in_log then
      local d, what = l:match("^%s*[-*]%s+(%d%d%d%d%-%d%d%-%d%d)[^:]*%d:%d%d:%s*(.-)%s*$")
      if d and d >= from and d <= to then
        local a, b = what:match("^(.-)%s*→%s*(.+)$")
        local created = what:match("^created in (.+)$")
        if created then
          table.insert(out, { to = created })
        elseif a and not a:match(":") then -- "project: a → b" isn't a move
          table.insert(out, { from = a, to = b })
        end
      end
    end
  end
  return out
end

--- The standup for `iso` (default today).
---@param root string
---@param iso? string
---@return logpose.Standup
function M.collect(root, iso)
  iso = iso or date.today()
  local cfg = config.get()
  local board = cfg.board
  local taskfile = require("logpose.taskfile")
  local daily = require("logpose.notes.daily")
  local since = date.prev_workday(iso, cfg.workdays)
  local until_ = date.add_days(iso, -1)
  local items = require("logpose.index").build(root)
  local s = { date = iso, since = since, yesterday = {}, today = {}, blockers = {} }
  local done_label = taskfile.label(board.done)

  local today_note = fs.normalize(daily.path(iso, root))
  local has_today_note = fs.exists(today_note)
  -- no daily note for today yet: the to-dos it would carry over are today's plan
  local plan_note = today_note
  if not has_today_note then
    local prev = daily.previous(root, iso)
    plan_note = prev and fs.normalize(prev) or nil
  end

  -- a daily note's line belongs to the project its #tag names
  local known = {}
  for _, name in ipairs(require("logpose.search").projects(root, items)) do
    known[name] = true
  end
  local function project_of(it)
    if it.project then
      return it.project
    end
    for _, t in ipairs(it.tags or {}) do
      if known[t] then
        return t
      end
    end
  end

  for _, it in ipairs(items) do
    local file = it.file and fs.normalize(it.file)
    if it.kind == "task" then
      local lines = fs.read_lines(it.file) or {}
      local m = moves(lines, since, until_)
      if #m > 0 then
        local first, last = m[1], m[#m]
        local from = first.from
        local note = from and (from .. " → " .. last.to) or ("new · " .. last.to)
        if from ~= last.to then
          table.insert(s.yesterday, {
            text = it.text,
            note = note,
            project = project_of(it),
            file = it.file,
            done = last.to == done_label,
          })
        end
      elseif it.status == board.done and it.done_date and it.done_date >= since and it.done_date <= until_ then
        table.insert(
          s.yesterday,
          { text = it.text, note = "→ " .. done_label, project = project_of(it), file = it.file, done = true }
        )
      end
      if not it.archived and it.status ~= board.done then
        if it.status == board.start then
          table.insert(
            s.today,
            { text = it.text, note = taskfile.label(board.start), project = project_of(it), file = it.file }
          )
        elseif it.due and it.due <= iso then
          local w = date.due(it.due, iso)
          table.insert(s.today, { text = it.text, note = w, project = project_of(it), file = it.file })
        end
        if it.blocked then
          table.insert(s.blockers, {
            text = it.text,
            note = it.blocked ~= "yes" and it.blocked or nil,
            project = project_of(it),
            file = it.file,
          })
        end
      end
    elseif it.kind == "note" and it.file_type == "meeting" and it.date then
      local e = { text = it.title or it.text, note = "meeting", project = project_of(it), file = it.file, lnum = 1 }
      if it.date >= since and it.date <= until_ then
        table.insert(s.yesterday, e)
      elseif it.date == iso then
        table.insert(s.today, e)
      end
    elseif it.kind == "todo" and it.file_type == "daily" then
      if it.checked and it.date and it.date >= since and it.date <= until_ and not it.done_by_task then
        table.insert(
          s.yesterday,
          { text = it.text, note = "to-do", project = project_of(it), file = it.file, lnum = it.lnum, done = true }
        )
      elseif not it.checked and file == plan_note then
        table.insert(
          s.today,
          { text = it.text, note = "to-do", project = project_of(it), file = it.file, lnum = it.lnum }
        )
      end
    elseif it.kind == "line" and it.file_type == "daily" and it.section == "blockers" and file == plan_note then
      table.insert(
        s.blockers,
        { text = (it.text:gsub("^%[.%]%s*", "")), project = project_of(it), file = it.file, lnum = it.lnum }
      )
    end
  end
  for _, list in ipairs({ s.yesterday, s.today, s.blockers }) do
    table.sort(list, function(a, b)
      local pa, pb = a.project or "\255", b.project or "\255"
      if pa ~= pb then
        return pa < pb
      end
      return a.text:lower() < b.text:lower()
    end)
  end
  return s
end

--- The standup as markdown, to paste where your team does standups.
---@param s logpose.Standup
---@return string[]
function M.markdown(s)
  local group = config.get().standup.group_by_project
  local out = { "# Standup " .. s.date }
  for _, part in ipairs({ { "Yesterday", s.yesterday }, { "Today", s.today }, { "Blockers", s.blockers } }) do
    table.insert(out, "")
    table.insert(out, "## " .. part[1])
    table.insert(out, "")
    if #part[2] == 0 then
      table.insert(out, "- (none)")
    end
    local current = false
    for _, e in ipairs(part[2]) do
      if group and e.project ~= current then
        current = e.project
        if out[#out] ~= "" then
          table.insert(out, "")
        end
        table.insert(out, "### " .. (e.project or "other"))
        table.insert(out, "")
      end
      local text = e.text .. (e.note and (" (" .. e.note .. ")") or "")
      table.insert(out, "- " .. text)
    end
  end
  return (require("logpose.markdown").tidy(out))
end

--- Copy the standup for `iso` to the clipboard (and the unnamed register).
---@param root string
---@param iso? string
function M.copy(root, iso)
  local text = table.concat(M.markdown(M.collect(root, iso)), "\n")
  vim.fn.setreg('"', text)
  pcall(vim.fn.setreg, "+", text)
  ui.notify("logpose: standup copied", vim.log.levels.INFO)
end

--- `:Logpose standup`: the standup on the today screen. `!` copies it; a date shows that day's.
---@param opts logpose.CommandOpts
function M.command(opts)
  local iso = opts.args[1]
  if iso == nil or iso == "today" then
    iso = nil
  elseif not date.is_iso(iso) then
    error(("logpose: invalid date %q (use YYYY-MM-DD)"):format(iso), 0)
  end
  config.with_root(ui.safely(function(root)
    if opts.bang then
      return M.copy(root, iso)
    end
    if not iso or iso == date.today() then
      return require("logpose.today").open(root, { focus = "standup" })
    end
    local lines = M.markdown(M.collect(root, iso))
    ui.scratch(lines, {
      name = "logpose://standup/" .. iso,
      filetype = "markdown",
      height = math.min(#lines + 1, 25),
      locked = true,
    })
  end))
end

return M

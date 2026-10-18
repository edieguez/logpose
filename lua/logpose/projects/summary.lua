--- What's going on in each project: the counts, the one-line summary and the details the
--- manager screen shows.
local config = require("logpose.config")
local date = require("logpose.util.date")
local project = require("logpose.project")

local M = {}

--- Tasks due within this many days count as "due soon".
M.DUE_SOON_DAYS = 3

---@class logpose.ProjectEntry
---@field file string
---@field lnum integer
---@field title string
---@field note? string   extra text (block reason, due date…)

---@class logpose.ProjectStats
---@field name string
---@field title string            display name (page title, else the name)
---@field description? string
---@field paths string[]
---@field archived boolean
---@field merged_into? string
---@field page? string            path of its project page
---@field open integer            tasks not done
---@field doing integer           tasks in the start column (In progress)
---@field blocked integer
---@field overdue integer
---@field due_soon integer
---@field done integer
---@field meetings integer
---@field notes integer           other notes
---@field mtime integer           newest change to any of its files (0: none)
---@field last? string            that as "today", "3d ago"…
---@field stale boolean           nothing changed for `review.stale_days`
---@field in_progress logpose.ProjectEntry[]
---@field blocked_list logpose.ProjectEntry[]
---@field due_list logpose.ProjectEntry[]   overdue and due soon, soonest first
---@field last_meeting? logpose.ProjectEntry
---@field recent_notes logpose.ProjectEntry[]

--- "today", "yesterday", "3d ago", "2w ago", "4mo ago".
---@param mtime integer
---@param now integer
---@return string
function M.ago(mtime, now)
  local days = math.floor((now - mtime) / 86400)
  if os.date("%Y-%m-%d", mtime) == os.date("%Y-%m-%d", now) then
    return "today"
  elseif days <= 1 then
    return "yesterday"
  elseif days < 14 then
    return days .. "d ago"
  elseif days < 60 then
    return math.floor(days / 7) .. "w ago"
  elseif days < 730 then
    return math.floor(days / 30) .. "mo ago"
  end
  return math.floor(days / 365) .. "y ago"
end

--- Everything the manager shows, one entry per project (archived included),
--- most recently active first.
---@param root string
---@param today? string
---@return logpose.ProjectStats[]
function M.stats(root, today)
  today = today or date.today()
  local cfg = config.get()
  local pages = project.pages(root)
  local uv = vim.uv or vim.loop
  local by_name, list = {}, {}
  local function entry(name)
    if not by_name[name] then
      local page = pages[name] or {}
      by_name[name] = {
        name = name,
        title = page.title or name,
        description = page.description,
        paths = page.paths or {},
        archived = page.archived or false,
        merged_into = page.merged_into,
        page = page.path,
        open = 0,
        doing = 0,
        blocked = 0,
        overdue = 0,
        due_soon = 0,
        done = 0,
        meetings = 0,
        notes = 0,
        mtime = 0,
        in_progress = {},
        blocked_list = {},
        due_list = {},
        recent_notes = {},
      }
      table.insert(list, by_name[name])
    end
    return by_name[name]
  end
  for _, name in ipairs(project.known(root, { archived = true })) do
    entry(name)
  end
  local mtimes = {}
  local function mtime(path)
    if mtimes[path] == nil then
      local st = uv.fs_stat(path)
      mtimes[path] = st and st.mtime.sec or 0
    end
    return mtimes[path]
  end
  for _, it in ipairs(require("logpose.index").build(root)) do
    local name = it.kind == "note" and it.project and project.normalize(it.project)
    if name then
      local e = entry(name)
      local ref = { file = it.file, lnum = it.lnum or 1, title = it.title or vim.fs.basename(it.file) }
      if it.note_type == "task" then
        if it.archived or it.status == cfg.board.done then
          e.done = e.done + 1
        else
          e.open = e.open + 1
          if it.status == cfg.board.start then
            e.doing = e.doing + 1
            table.insert(e.in_progress, ref)
          end
          if it.blocked then
            e.blocked = e.blocked + 1
            table.insert(e.blocked_list, vim.tbl_extend("force", ref, { note = it.blocked }))
          end
          if it.due and it.due:match("^%d%d%d%d%-%d%d%-%d%d$") then
            local d = date.diff_days(today, it.due)
            if d < 0 then
              e.overdue = e.overdue + 1
            elseif d <= M.DUE_SOON_DAYS then
              e.due_soon = e.due_soon + 1
            end
            if d <= M.DUE_SOON_DAYS then
              table.insert(e.due_list, vim.tbl_extend("force", ref, { due = it.due, days = d }))
            end
          end
        end
      elseif it.note_type == "meeting" then
        e.meetings = e.meetings + 1
        if not e.last_meeting or (it.date or "") > (e.last_meeting.date or "") then
          e.last_meeting = vim.tbl_extend("force", ref, { date = it.date })
        end
      elseif it.note_type ~= "project" then
        e.notes = e.notes + 1
        table.insert(e.recent_notes, vim.tbl_extend("force", ref, { mtime = mtime(it.file) }))
      end
      e.mtime = math.max(e.mtime, mtime(it.file))
    end
  end
  local now = date._now()
  local stale_after = cfg.review.stale_days * 86400
  for _, e in ipairs(list) do
    if e.page then
      e.mtime = math.max(e.mtime, mtime(e.page))
    end
    e.last = e.mtime > 0 and M.ago(e.mtime, now) or nil
    e.stale = e.mtime > 0 and now - e.mtime > stale_after
    table.sort(e.due_list, function(a, b)
      return a.due < b.due
    end)
    table.sort(e.recent_notes, function(a, b)
      return a.mtime > b.mtime
    end)
    while #e.recent_notes > 3 do
      table.remove(e.recent_notes)
    end
  end
  table.sort(list, function(a, b)
    if a.mtime ~= b.mtime then
      return a.mtime > b.mtime
    end
    return a.name < b.name
  end)
  return list
end

--- The one-line summary of a project, as highlighted chunks:
--- "5 open (1 in progress) · 1 overdue · 1 blocked · 2 meetings".
---@param e logpose.ProjectStats
---@return { [1]: string, [2]: string? }[]
function M.summary(e)
  local parts = {}
  local function add(n, what, hl)
    if n > 0 then
      table.insert(parts, { ("%d %s"):format(n, what), hl })
    end
  end
  if e.open > 0 then
    local doing = require("logpose.taskfile").label(config.get().board.start):lower()
    add(e.open, e.doing > 0 and not e.archived and ("open (%d %s)"):format(e.doing, doing) or "open")
  end
  if not e.archived then
    add(e.overdue, "overdue", "DiagnosticError")
    add(e.due_soon, "due soon", "DiagnosticWarn")
    add(e.blocked, "blocked", "DiagnosticError")
  end
  if e.open == 0 then
    add(e.done, "done", "Comment")
  end
  add(e.meetings, e.meetings == 1 and "meeting" or "meetings")
  add(e.notes, e.notes == 1 and "note" or "notes")
  if #parts == 0 then
    return { { e.page and "project page only" or "nothing yet", "Comment" } }
  end
  local out = {}
  for i, p in ipairs(parts) do
    if i > 1 then
      table.insert(out, { " · ", "Comment" })
    end
    table.insert(out, p)
  end
  return out
end

---@class logpose.ProjectsLine
---@field chunks { [1]: string, [2]: string? }[]
---@field project? string    a project row
---@field archived? boolean
---@field file? string       a detail line that opens a file
---@field lnum? integer

--- What's going on in a project, as lines (shown under an expanded row in the manager).
---@param e logpose.ProjectStats
---@param indent? string
---@return logpose.ProjectsLine[]
function M.details(e, indent)
  indent = indent or ""
  local lines = {} ---@type logpose.ProjectsLine[]
  local function add(chunks, extra)
    table.insert(chunks, 1, { indent })
    table.insert(lines, vim.tbl_extend("force", { chunks = chunks }, extra or {}))
  end
  if e.description then
    add({ { e.description, "Comment" } })
  end
  if e.title ~= e.name then
    add({ { "name: ", "Comment" }, { e.name } })
  end
  if #e.paths > 0 then
    add({ { "repo: ", "Comment" }, { table.concat(e.paths, ", ") } })
  end
  if e.merged_into then
    add({ { "merged into ", "Comment" }, { e.merged_into, "Identifier" } })
  end
  local function section(title, entries, fmt)
    if #entries == 0 then
      return
    end
    add({ { title, "Title" } })
    for _, x in ipairs(entries) do
      local text, hl, note_hl = fmt(x)
      add({ { "  • " }, { x.title, hl }, { text or "", note_hl or "Comment" } }, { file = x.file, lnum = x.lnum })
    end
  end
  local doing = require("logpose.taskfile").label(config.get().board.start)
  section(doing, e.in_progress, function()
    return nil
  end)
  section("Blocked", e.blocked_list, function(x)
    return "  " .. x.note, nil, "DiagnosticError"
  end)
  section("Due", e.due_list, function(x)
    local text, urgency = date.due(x.due)
    return "  " .. text, nil, urgency == "overdue" and "DiagnosticError" or "DiagnosticWarn"
  end)
  if e.last_meeting then
    section("Last meeting", { e.last_meeting }, function(x)
      return x.date and ("  " .. x.date) or nil
    end)
  end
  section("Recent notes", e.recent_notes, function()
    return nil
  end)
  if #lines == 0 then
    add({ { "Nothing here yet. n opens its project page.", "Comment" } })
  end
  return lines
end

return M

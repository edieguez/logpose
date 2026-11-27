--- The daily status, written into the daily note: `## Yesterday` (what happened since the
--- previous workday), `## Today` (tasks in progress, due or done today) and `## Blockers` (blocked
--- tasks). Only your tasks count (`daily.status.only_mine`): assigned to `me`, or to nobody.
--- A line logpose writes reads `- project: <link> — note`: the link names the task, the meeting
--- or the daily note a to-do was checked in, and it's how a refresh finds the line again.
--- Everything else in those sections is yours (your own lines, the sub-bullets under a line):
--- logpose rewrites its lines and leaves the rest alone.
---   Yesterday  filled when the note is made; `refresh!` rebuilds it
---   Today      today's note only: every task line follows its task; new ones are added
---   Blockers   today's note only: a task no longer blocked loses its line (unless you wrote
---              under it)
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

M.SEP = " — "
M.YESTERDAY, M.TODAY, M.TODOS, M.BLOCKERS = "Yesterday", "Today", "To-dos", "Blockers"

---@class logpose.StatusEntry
---@field key string       the file it comes from (and, for a checked to-do, its text)
---@field file string
---@field label string
---@field note string      what happened: "TODO → In progress", "meeting", "waiting on CI"
---@field project? string

---@class logpose.Status
---@field date string
---@field since string     the previous workday: Yesterday covers since .. date - 1
---@field yesterday logpose.StatusEntry[]
---@field today logpose.StatusEntry[]
---@field blockers logpose.StatusEntry[]
---@field tasks table<string, logpose.StatusEntry>  every task as it is now, by key

--- A label as it can go inside a link: no brackets or pipes, one space at a time.
---@param s string
---@return string
local function clean(s)
  return vim.trim((s:gsub("[%[%]|]", ""):gsub("%s+", " ")))
end

--- A to-do's text as it reads in the status: links as their labels, without `#tags`, `@` and
--- `due:` (they'd count again in today's note). Issue numbers (`#12`) stay.
---@param text string
---@return string
function M.plain(text)
  local t = require("logpose.util.text")
  local s = text:gsub("%[%[(.-)%]%]", function(inner)
    local label = inner:match("|(.*)$")
    if label then
      return label
    end
    return (vim.fn.fnamemodify((inner:gsub("#.*$", "")), ":t"))
  end)
  s = s:gsub("%[([^%]]*)%]%b()", "%1")
  s = (" " .. s):gsub("([%s%(%[,;])#(" .. t.TAG .. ")", function(pre, tag)
    return tag:match("^%d+$") and (pre .. "#" .. tag) or pre
  end)
  s = s:gsub("([%s%(%[,;])@(" .. t.HANDLE .. ")", "%1%2")
  s = s:gsub("due:%d%d%d%d%-%d%d%-%d%d", "")
  return clean(s)
end

--- Status moves in a task's `## Log` between `from` and `to` (inclusive), oldest first.
---@param lines string[]
---@param from string
---@param to string
---@return { from?: string, to: string }[]
function M.moves(lines, from, to)
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

--- What logpose writes about a task as it is now: "In progress", "TODO, due today", "→ Done".
---@param it logpose.Item
---@param iso string
---@return string
local function task_state(it, iso)
  local board = config.get().board
  local label = require("logpose.taskfile").label(it.status or "")
  if it.status == board.done then
    return it.done_date == iso and ("→ " .. label) or label
  end
  if it.due and it.due <= iso then
    return label .. ", " .. date.due(it.due, iso)
  end
  return label
end

--- The status for `iso` (default today).
---@param root string
---@param iso? string
---@param items? logpose.Item[]
---@return logpose.Status
function M.collect(root, iso, items)
  iso = iso or date.today()
  local cfg = config.get()
  local board = cfg.board
  local taskfile = require("logpose.taskfile")
  items = items or require("logpose.index").build(root)
  local since = date.prev_workday(iso, cfg.workdays)
  local until_ = date.add_days(iso, -1)
  local s = { date = iso, since = since, yesterday = {}, today = {}, blockers = {}, tasks = {} }
  local done_label = taskfile.label(board.done)
  -- someone else's task isn't your status (`daily.status.only_mine`)
  local people = require("logpose.people")
  local me
  local function yours(it)
    if not cfg.daily.status.only_mine then
      return true
    end
    if me == nil then
      me = people.me() or false
    end
    return people.is_mine(it.assignee, me)
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
  local function entry(it, label, note, key)
    return {
      key = key or fs.normalize(it.file),
      file = it.file,
      label = clean(label),
      note = note,
      project = project_of(it),
    }
  end

  for _, it in ipairs(items) do
    if it.kind == "task" and yours(it) then
      local title = it.title or it.text
      local m = M.moves(fs.read_lines(it.file) or {}, since, until_)
      if #m > 0 then
        local first, last = m[1], m[#m]
        if first.from ~= last.to then
          local note = first.from and (first.from .. " → " .. last.to) or ("new · " .. last.to)
          table.insert(s.yesterday, entry(it, title, note))
        end
      elseif it.status == board.done and it.done_date and it.done_date >= since and it.done_date <= until_ then
        table.insert(s.yesterday, entry(it, title, "→ " .. done_label))
      end
      if not it.archived then
        local now = entry(it, title, task_state(it, iso))
        s.tasks[now.key] = now
        local done = it.status == board.done
        local closed = taskfile.is_closed(it.status) -- done, or cancelled: no longer to do
        if
          (not closed and (it.status == board.start or (it.due and it.due <= iso)))
          or (done and it.done_date == iso)
        then
          table.insert(s.today, now)
        end
        if it.blocked and not closed then
          table.insert(s.blockers, entry(it, title, it.blocked ~= "yes" and it.blocked or "blocked"))
        end
      end
    elseif it.kind == "note" and it.file_type == "meeting" and it.date then
      if it.date >= since and it.date <= until_ then
        table.insert(s.yesterday, entry(it, it.title or it.text, "meeting"))
      end
    elseif it.kind == "todo" and it.file_type == "daily" and it.checked and it.date then
      -- a to-do made into a task: the task speaks for it
      if it.date >= since and it.date <= until_ and not it.task_link and not it.done_by_task then
        local label = M.plain(it.text)
        if label ~= "" then
          table.insert(s.yesterday, entry(it, label, "to-do done", fs.normalize(it.file) .. "\n" .. label))
        end
      end
    end
  end
  for _, list in ipairs({ s.yesterday, s.today, s.blockers }) do
    table.sort(list, function(a, b)
      local pa, pb = a.project or "\255", b.project or "\255"
      if pa ~= pb then
        return pa < pb
      end
      if a.label:lower() ~= b.label:lower() then
        return a.label:lower() < b.label:lower()
      end
      return a.key < b.key
    end)
  end
  return s
end

--- A line logpose writes: `- project: <link> — note`, the link made from `from` (the daily note).
---@param e logpose.StatusEntry
---@param from string
---@param root string
---@return string
function M.render(e, from, root)
  local prefix = e.project and (e.project .. ": ") or ""
  return "- " .. prefix .. require("logpose.link").make(from, e.file, e.label, root) .. M.SEP .. e.note
end

--- Parse a line logpose wrote; nil for any other line.
---@param line string
---@return { project?: string, link: { target: string, style: string }, label: string, note: string }?
function M.parse(line)
  local body = line:match("^%- (.+)$")
  if not body then
    return nil
  end
  local project, rest = body:match("^([^%s:%[%]]+): (.+)$")
  rest = rest or body
  local l
  for _, cand in ipairs(require("logpose.index").links_in(rest)) do
    if cand.s == 1 then
      l = cand
    end
  end
  if not l then
    return nil
  end
  local note = rest:sub(l.e):match("^" .. M.SEP .. "(.*)$")
  if not note then
    return nil
  end
  local raw = rest:sub(1, l.e - 1)
  local label
  if l.style == "wiki" then
    label = raw:match("^%[%[[^|]*|(.*)%]%]$") or raw:match("^%[%[(.*)%]%]$")
  else
    label = raw:match("^%[(.-)%]%(")
  end
  return { project = project, link = l, label = label or "", note = note }
end

--- Find the lines logpose wrote, from a note at `from`: `key_of(line)` gives a line's key and
--- what it links (task, meeting or daily), nil for a line that's yours.
---@param root string
---@param from string
---@param items? logpose.Item[]
---@return { key_of: fun(line: string): string?, string? }
function M.context(root, from, items)
  items = items or require("logpose.index").build(root)
  local kinds = {}
  for _, it in ipairs(items) do
    if it.kind == "task" then
      kinds[fs.normalize(it.file)] = "task"
    elseif it.kind == "note" and (it.file_type == "meeting" or it.file_type == "daily") then
      kinds[fs.normalize(it.file)] = it.file_type
    end
  end
  local by_name
  return {
    key_of = function(line)
      local p = M.parse(line)
      if not p then
        return nil
      end
      by_name = by_name or require("logpose.links").names(items)
      local file = require("logpose.links").resolve(root, from, p.link, by_name)
      file = file and fs.normalize(file)
      local kind = file and kinds[file]
      if not kind then
        return nil
      end
      return kind == "daily" and (file .. "\n" .. p.label) or file, kind
    end,
  }
end

local function is_top(l)
  return l:match("^%S") ~= nil
end

--- `## name` (any case) outside code: its row and the last row before the next `#`/`##` heading.
---@param lines string[]
---@param name string
---@param code table<integer, boolean>
---@return integer? head, integer? last
local function find_section(lines, name, code)
  local want = name:lower()
  for i, l in ipairs(lines) do
    local h = not code[i] and l:match("^##%s+(.-)%s*$")
    if h and h:lower() == want then
      local j = i + 1
      while j <= #lines and (code[j] or not lines[j]:match("^##?%s")) do
        j = j + 1
      end
      return i, j - 1
    end
  end
end

--- Where a missing section goes: after the first of `after` there is, else after the title (or
--- the frontmatter, or at the top). The row to insert after.
---@param lines string[]
---@param code table<integer, boolean>
---@param after string[]
---@return integer
local function place(lines, code, after)
  for _, name in ipairs(after) do
    local _, last = find_section(lines, name, code)
    if last then
      return last
    end
  end
  for i, l in ipairs(lines) do
    if not code[i] and l:match("^#%s") then
      return i
    end
  end
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        return i
      end
    end
  end
  return 0
end

--- Lines with a row to follow (the cursor) as lines go in and out above it.
---@param lines string[]
---@param row? integer
local function editor(lines, row)
  local e = { lines = lines, row = row }
  function e.insert(pos, new)
    for k, l in ipairs(new) do
      table.insert(e.lines, pos + k - 1, l)
    end
    if e.row and e.row >= pos then
      e.row = e.row + #new
    end
  end
  function e.remove(pos)
    table.remove(e.lines, pos)
    if e.row and e.row > pos then
      e.row = e.row - 1
    end
  end
  return e
end

---@class logpose.StatusMerge
---@field key_of fun(line: string): string?, string?
---@field lookup? fun(key: string): string?      a line for a key that isn't wanted (Today: the task now)
---@field drop? fun(key: string, kind: string): boolean  drop a line no longer wanted (unless you wrote under it)
---@field after string[]                          sections a missing one goes after

--- Bring section `name` in line with `wanted` ({ key, line }): its lines are rewritten, missing
--- ones added at its end, a missing section added with them.
---@param e table editor
---@param name string
---@param wanted { key: string, line: string }[]
---@param opts logpose.StatusMerge
local function merge(e, name, wanted, opts)
  local lines = e.lines
  local code = require("logpose.markdown").code_rows(lines)
  local head, last = find_section(lines, name, code)
  if not head then
    if #wanted == 0 then
      return
    end
    local at = place(lines, code, opts.after)
    local block = { "", "## " .. name, "" }
    for _, w in ipairs(wanted) do
      table.insert(block, w.line)
    end
    if lines[at + 1] ~= nil then
      table.insert(block, "")
    end
    e.insert(at + 1, block)
    return
  end
  local by_key = {}
  for _, w in ipairs(wanted) do
    by_key[w.key] = w.line
  end
  local seen, drops, end_row = {}, {}, head
  local i = head + 1
  while i <= last do
    local l = lines[i]
    local j = i + 1 -- the lines under it: indented, not blank
    while j <= last and lines[j]:match("^%s+%S") do
      j = j + 1
    end
    if l:match("%S") then
      end_row = j - 1
    end
    local key, kind
    if not code[i] and is_top(l) then
      key, kind = opts.key_of(l)
    end
    if key then
      if by_key[key] then
        lines[i] = by_key[key]
        seen[key] = true
      elseif opts.drop and opts.drop(key, kind) and j == i + 1 then
        table.insert(drops, i)
      elseif opts.lookup then
        lines[i] = opts.lookup(key) or l
      end
    end
    i = j
  end
  local new = {}
  for _, w in ipairs(wanted) do
    if not seen[w.key] then
      seen[w.key] = true
      table.insert(new, w.line)
    end
  end
  if #new > 0 then
    if end_row == head then
      table.insert(new, 1, "")
    end
    e.insert(end_row + 1, new)
  end
  for k = #drops, 1, -1 do
    e.remove(drops[k])
  end
end

---@class logpose.StatusApply
---@field yesterday? "fill"|"rebuild"  fill: add what's missing; rebuild: also drop what didn't happen
---@field row? integer                 a row to follow (the cursor)

--- The note's lines with the status brought up to date: Yesterday as `opts.yesterday` says,
--- Today and Blockers when `iso` is today.
---@param lines string[]
---@param root string
---@param path string the daily note
---@param iso string its date
---@param opts? logpose.StatusApply
---@return string[] lines, integer? row
function M.apply(lines, root, path, iso, opts)
  opts = opts or {}
  local items = require("logpose.index").build(root)
  local s = M.collect(root, iso, items)
  local ctx = M.context(root, path, items)
  local e = editor(vim.deepcopy(lines), opts.row)
  local function wanted(list)
    return vim.tbl_map(function(en)
      return { key = en.key, line = M.render(en, path, root) }
    end, list)
  end
  if opts.yesterday then
    merge(e, M.YESTERDAY, wanted(s.yesterday), {
      key_of = ctx.key_of,
      drop = opts.yesterday == "rebuild" and function()
        return true
      end or nil,
      after = {},
    })
  end
  if iso == date.today() then
    merge(e, M.TODAY, wanted(s.today), {
      key_of = ctx.key_of,
      lookup = function(key)
        return s.tasks[key] and M.render(s.tasks[key], path, root)
      end,
      after = { M.YESTERDAY },
    })
    merge(e, M.BLOCKERS, wanted(s.blockers), {
      key_of = ctx.key_of,
      drop = function(_, kind)
        return kind == "task"
      end,
      after = { M.TODOS, M.TODAY, M.YESTERDAY },
    })
  end
  return e.lines, e.row
end

--- Bring the status in the daily note at `path` up to date (see `apply`; `full` rebuilds
--- Yesterday). A raw update: `modified:` stays. Written only when something changes.
---@param root string
---@param path string
---@param iso string
---@param full? boolean
---@return "file"|"buffer"|nil changed
function M.refresh(root, path, iso, full)
  local ok, err, changed = fs.update_lines(path, function(lines)
    local new = M.apply(lines, root, path, iso, { yesterday = full and "rebuild" or nil })
    if vim.deep_equal(new, lines) then
      return nil
    end
    return new
  end, { tidy = true, raw = true })
  if not ok then
    error(err, 0)
  end
  return changed
end

--- Lines under a note's `## Blockers` without the ones logpose wrote (they're worked out again
--- in the next note), nor the lines under them.
---@param lines string[] the section's lines (`daily.blockers`)
---@param root string
---@param from string the note they're from
---@return string[]
function M.yours(lines, root, from)
  local ctx = M.context(root, from)
  local code = require("logpose.markdown").code_rows(lines)
  local out, skip = {}, false
  for i, l in ipairs(lines) do
    if is_top(l) then
      local _, kind
      if not code[i] then
        _, kind = ctx.key_of(l)
      end
      skip = kind == "task"
    end
    if not skip then
      table.insert(out, l)
    end
  end
  return out
end

--- The status as written in the note, as markdown to paste: Yesterday, Today (with the open
--- to-dos of `## To-dos`) and Blockers, links as their labels, grouped by project unless
--- `daily.status.group_by_project = false`.
---@param lines string[] the daily note
---@param root string
---@param path string
---@param iso string
---@return string[]
function M.markdown(lines, root, path, iso)
  local index = require("logpose.index")
  local items = index.build(root)
  local ctx = M.context(root, path, items)
  local code = require("logpose.markdown").code_rows(lines)
  local known = {}
  for _, name in ipairs(require("logpose.search").projects(root, items)) do
    known[name] = true
  end
  local function readable(s)
    s = s:gsub("%[%[(.-)%]%]", function(inner)
      return inner:match("|(.*)$") or (vim.fn.fnamemodify((inner:gsub("#.*$", "")), ":t"))
    end)
    return (s:gsub("%[([^%]]*)%]%b()", "%1"))
  end
  local function project_of(l)
    local p = l:match("^[-*+]%s+([^%s:%[%]]+): ")
    if p and known[p] then
      return p
    end
    for _, t in ipairs(index.tags_in(l)) do
      if known[t] then
        return t
      end
    end
  end

  --- The items of a section: { text, project, children }.
  local function section(name, as_item, keys)
    local out = {}
    local head, last = find_section(lines, name, code)
    if not head then
      return out
    end
    local cur
    for i = head + 1, last do
      local l = lines[i]
      if code[i] or not l:match("%S") then
        if code[i] and cur then
          table.insert(cur.children, l)
        end
      elseif is_top(l) then
        cur = as_item(l, i)
        if cur then
          cur.children = {}
          table.insert(out, cur)
          if keys then
            keys[ctx.key_of(l) or ""] = true
          end
        end
      elseif cur and not l:match("^%s+→%s") then
        table.insert(cur.children, readable(l))
      end
    end
    return out
  end
  local function status_item(l)
    local p = M.parse(l)
    if p then
      return { text = p.label .. " (" .. p.note .. ")", project = p.project }
    end
    return { text = readable((l:gsub("^[-*+]%s+", ""))), project = project_of(l) }
  end

  local today_keys = {}
  local yesterday = section(M.YESTERDAY, status_item)
  local today = section(M.TODAY, status_item, today_keys)
  -- the open to-dos, but not one made into a task that's already there
  local todos = require("logpose.todos")
  local linked = {}
  local by_name
  for _, t in ipairs(todos.linked(lines)) do
    by_name = by_name or require("logpose.links").names(items)
    local file = require("logpose.links").resolve(root, path, t.link, by_name)
    if file and today_keys[fs.normalize(file)] then
      linked[t.row] = true
    end
  end
  vim.list_extend(
    today,
    section(M.TODOS, function(l, i)
      local t = todos.parse(l)
      if t and not t.checked and not linked[i] and vim.trim(t.text) ~= "" then
        return { text = readable(t.text) .. " (to-do)", project = project_of(l) }
      end
    end)
  )
  local blockers = section(M.BLOCKERS, status_item)

  local group = config.get().daily.status.group_by_project
  local out = { "# Status " .. iso }
  for _, part in ipairs({ { M.YESTERDAY, yesterday }, { M.TODAY, today }, { M.BLOCKERS, blockers } }) do
    vim.list_extend(out, { "", "## " .. part[1], "" })
    local list = part[2]
    if #list == 0 then
      table.insert(out, "- (none)")
    end
    if group then
      local order, by = {}, {}
      for _, it in ipairs(list) do
        local p = it.project or "\255"
        if not by[p] then
          by[p] = {}
          table.insert(order, p)
        end
        table.insert(by[p], it)
      end
      table.sort(order)
      for _, p in ipairs(order) do
        vim.list_extend(out, { "", "### " .. (p == "\255" and "other" or p), "" })
        for _, it in ipairs(by[p]) do
          table.insert(out, "- " .. it.text)
          vim.list_extend(out, it.children)
        end
      end
    else
      for _, it in ipairs(list) do
        table.insert(out, "- " .. it.text)
        vim.list_extend(out, it.children)
      end
    end
  end
  return (require("logpose.markdown").tidy(out))
end

--- Copy the status of the daily note at `path` to the clipboard (and the unnamed register).
---@param root string
---@param path string
---@param iso string
function M.copy(root, path, iso)
  local text = table.concat(M.markdown(fs.current_lines(path) or {}, root, path, iso), "\n")
  vim.fn.setreg('"', text)
  local ok = pcall(vim.fn.setreg, "+", text)
  ui.notify(
    ok and "logpose: status copied" or "logpose: status copied to the unnamed register (no clipboard)",
    vim.log.levels.INFO
  )
end

return M

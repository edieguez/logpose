--- Task files: one markdown file per task in `dirs.tasks`, with the board column in `status:`.
---
---   ---
---   title: "Fix flaky test"
---   status: in-progress
---   project: acme
---   assignee: Ana López       (optional: who does it; nobody means you, `tasks.unassigned_mine`)
---   stakeholders: [Bob]       (optional: who cares about it)
---   tags: [perf]
---   due: 2026-10-20
---   blocked: waiting on ana
---   cancelled:                (only once cancelled: the reason, "yes" when none; status: cancelled)
---   created: 2026-10-15T09:05
---   modified: 2026-10-16T15:02
---   started: 2026-10-16
---   done:
---   ---
---   # Fix flaky test
---   …context…
---   ## Log
---   - 2026-10-16 09:10: TODO → In progress
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local text = require("logpose.util.text")

local M = {}

--- Frontmatter keys logpose writes, in order.
M.KEYS = {
  "title",
  "status",
  "project",
  "assignee",
  "stakeholders",
  "tags",
  "due",
  "blocked",
  "cancelled",
  "created",
  "modified",
  "started",
  "done",
  "order",
}

--- Keys written only when they have a value (a task is unassigned without them).
local OPTIONAL = { assignee = true, stakeholders = true, cancelled = true, modified = true, order = true }

--- Keys removed when cleared (rather than left empty).
local REMOVED = { order = true, cancelled = true }

---@class logpose.Task
---@field path string
---@field title string
---@field status string
---@field project? string
---@field assignee? string  who does it, as written (nil: nobody)
---@field stakeholders string[]  who cares about it, as written
---@field tags string[]
---@field due? string
---@field blocked? string  reason ("yes" when none was given)
---@field cancelled? string  why it was cancelled ("yes" when no reason was given)
---@field created? string
---@field started? string
---@field done? string
---@field order? number
---@field archived boolean
---@field since? string  day it entered its current column (from the log; else created)

---@return { key: string, label: string }[]
function M.columns()
  return vim.tbl_map(function(c)
    return { key = c.key, label = c.label or c.key }
  end, config.get().board.columns)
end

---@param key string
---@return integer?
function M.column_index(key)
  for i, c in ipairs(config.get().board.columns) do
    if c.key == key then
      return i
    end
  end
end

---@param key string
---@return string
function M.label(key)
  local i = M.column_index(key)
  if not i and key == config.get().board.cancelled then
    return "Cancelled"
  end
  return i and (config.get().board.columns[i].label or key) or key
end

--- Is a task with this status closed: done, or cancelled? (Done alone is what was finished.)
---@param status? string
---@return boolean
function M.is_closed(status)
  local board = config.get().board
  return status == board.done or status == board.cancelled
end

--- Is a task with this status cancelled?
---@param status? string
---@return boolean
function M.is_cancelled(status)
  return status ~= nil and status == config.get().board.cancelled
end

---@param root string
---@return string
function M.dir(root)
  return config.path("tasks", root)
end

---@param path string
---@param root string
---@return boolean
function M.is_task_file(path, root)
  local dir = fs.normalize(M.dir(root))
  path = fs.normalize(path)
  return vim.startswith(path, dir .. "/") and path:sub(-3) == ".md"
end

local str = text.nonempty

--- Parse a task from its lines.
---@param path string
---@param lines string[]
---@param root string
---@return logpose.Task
function M.parse(path, lines, root)
  local index = require("logpose.index")
  local fm = index.frontmatter(lines)
  local title = str(fm.title)
  if not title then
    for _, l in ipairs(lines) do
      local h = l:match("^#%s+(.+)$")
      if h then
        title = vim.trim(h)
        break
      end
    end
  end
  local tags = {}
  if type(fm.tags) == "table" then
    tags = vim.tbl_map(function(t)
      return (t:gsub("^#", "")):lower()
    end, fm.tags)
  end
  local archive = fs.join(M.dir(root), "archive") .. "/"
  local status = str(fm.status) or config.get().tasks.capture_status
  -- When did it reach its current column? The last "A → <label>" log line, else creation.
  local since
  local label = M.label(status)
  for _, l in ipairs(lines) do
    local day, to = l:match("^%- (%d%d%d%d%-%d%d%-%d%d) %d%d:%d%d: .- → (.+)$")
    if day and vim.trim(to) == label then
      since = day
    end
  end
  since = since or (str(fm.created) and fm.created:sub(1, 10)) or nil
  return {
    since = since,
    path = path,
    title = title or vim.fn.fnamemodify(path, ":t:r"),
    status = status,
    project = str(fm.project) and fm.project:lower() or nil,
    assignee = type(fm.assignee) == "string" and str(vim.trim(fm.assignee)) or nil,
    stakeholders = M.names(fm.stakeholders),
    tags = tags,
    due = str(fm.due) and date.is_iso(fm.due) and fm.due or nil,
    blocked = str(fm.blocked),
    cancelled = str(fm.cancelled),
    created = str(fm.created),
    started = str(fm.started),
    done = str(fm.done),
    order = tonumber(fm.order),
    archived = vim.startswith(fs.normalize(path), fs.normalize(archive)),
  }
end

--- A list of names from frontmatter: a list, or a comma-separated string.
---@param v any
---@return string[]
function M.names(v)
  local out = {}
  if type(v) == "string" then
    v = vim.split(v, ",", { plain = true })
  end
  for _, n in ipairs(type(v) == "table" and v or {}) do
    n = type(n) == "string" and vim.trim(n) or ""
    if n ~= "" then
      table.insert(out, n)
    end
  end
  return out
end

--- Every task file under `dirs.tasks` (archived ones only with `archived = true`).
---@param root string
---@param opts? { archived?: boolean }
---@return logpose.Task[]
-- Parsed tasks by path: { sec, nsec, size, at, task }. Valid while the file is unchanged on
-- disk and the options are the same table (parsing depends on the columns and capture status);
-- see `index.fresh` for when an entry is trusted.
local cache, cache_opts = {}, nil

function M.list(root, opts)
  opts = opts or {}
  local dir = M.dir(root)
  local out = {}
  if not fs.is_dir(dir) then
    return out
  end
  local cfg = config.get()
  if cache_opts ~= cfg then
    cache, cache_opts = {}, cfg
  end
  local uv = vim.uv or vim.loop
  -- Archived tasks live under tasks/archive/: don't even walk there unless they're wanted.
  local skip = not opts.archived and function(d)
    return d ~= "archive"
  end or nil
  local dirty = fs.modified_bufs()
  for name, kind in vim.fs.dir(dir, { depth = 4, skip = skip }) do
    if kind == "file" and name:sub(-3) == ".md" then
      local path = fs.join(dir, name)
      local buf = next(dirty) and dirty[fs.canonical(path)]
      local task
      if buf then
        -- unsaved edits: the buffer is the truth, and it isn't cached
        task = M.parse(path, vim.api.nvim_buf_get_lines(buf, 0, -1, false), root)
      else
        local st = uv.fs_stat(path)
        local hit = cache[path]
        if require("logpose.index").fresh(hit, st) then
          task = hit.task
        else
          task = M.parse(path, fs.read_lines(path) or {}, root)
          if st then
            cache[path] = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, at = os.time(), task = task }
          end
        end
      end
      if opts.archived or not task.archived then
        table.insert(out, task)
      end
    end
  end
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

--- Set `key` in the frontmatter of `lines` (creating the frontmatter / key in M.KEYS order).
---@param lines string[]
---@param key string
---@param value any nil/"" leaves the key empty
---@return string[]
function M.set_field(lines, key, value)
  -- `order` only exists while a card is placed by hand; other keys are kept, empty, when cleared
  local v = value
  if v == nil or v == "" then
    if REMOVED[key] then
      v = false -- removed
    else
      v = ""
    end
  end
  return require("logpose.frontmatter").set(lines, { [key] = v }, { order = M.KEYS })
end

--- Append `entry` to the `## Log` section (created at the end if missing).
---@param lines string[]
---@param entry string
---@return string[]
function M.append_log(lines, entry)
  local item = ("- %s %s: %s"):format(date.today(), date.now_hhmm():gsub("^(%d%d)(%d%d)$", "%1:%2"), entry)
  local head
  for i, l in ipairs(lines) do
    if l:match("^##%s+[Ll]og%s*$") then
      head = i
    end
  end
  if not head then
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    vim.list_extend(lines, { "", "## Log", item })
    return lines
  end
  local last = head
  for i = head + 1, #lines do
    if lines[i]:match("^#+%s") then
      break
    end
    if vim.trim(lines[i]) ~= "" then
      last = i
    end
  end
  table.insert(lines, last + 1, item)
  return lines
end

--- Apply `fn(lines)` to a task file (or its unsaved buffer).
---@param path string
---@param fn fun(lines: string[]): string[]?
local function update(path, fn)
  local ok, err = fs.update_lines(path, fn, { tidy = true })
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
end

--- Move a task to `status`, keeping `started`/`done` and the log in step. Moving it in or out of
--- Done checks or unchecks the to-dos it was made from (`sync.set_todos`).
---@param path string
---@param status string
---@return boolean changed
function M.set_status(path, status)
  if M.is_cancelled(status) then
    return M.set_cancelled(path, nil)
  end
  if not M.column_index(status) then
    error(("logpose: unknown board column %q"):format(status), 0)
  end
  local changed, was_done = false, false
  update(path, function(lines)
    local fm = require("logpose.index").frontmatter(lines)
    local from = str(fm.status) or config.get().tasks.capture_status
    if from == status then
      return nil
    end
    changed = true
    local board = config.get().board
    lines = M.set_field(lines, "status", status)
    if status == board.start and not str(fm.started) then
      lines = M.set_field(lines, "started", date.today())
    end
    if status == board.done then
      lines = M.set_field(lines, "done", date.today())
      if str(fm.blocked) then
        lines = M.set_field(lines, "blocked", nil) -- finished work isn't blocked
      end
    elseif str(fm.done) then
      lines = M.set_field(lines, "done", nil)
    end
    lines = M.set_field(lines, "order", nil)
    if M.is_cancelled(from) then
      lines = M.set_field(lines, "cancelled", nil) -- reopened
    end
    was_done = from == board.done
    return M.append_log(lines, ("%s → %s"):format(M.label(from), M.label(status)))
  end)
  -- in or out of Done: the to-dos it was made from follow
  local is_done = status == config.get().board.done
  if changed and was_done ~= is_done then
    local root = config.resolve_root()
    if root then
      local ok, err = pcall(require("logpose.sync").set_todos, root, fs.normalize(path), is_done)
      if not ok then
        require("logpose.util.ui").notify(require("logpose.util.ui").message(err), vim.log.levels.WARN)
      end
    end
  end
  return changed
end

--- Cancel a task (with a reason, or none): closed, but not done. `blocked` and `done` are
--- cleared, `started` kept; the log says `In progress → Cancelled`, then `cancelled: <reason>`.
--- Cancelling a cancelled task again only changes the reason. Moving it to a column
--- (`set_status`) reopens it.
---@param path string
---@param reason? string|false  false: no reason (an earlier one is dropped); nil: keep the reason
---@return boolean changed
function M.set_cancelled(path, reason)
  local none = reason == false
  reason = type(reason) == "string" and vim.trim(reason) or nil
  if reason == "" then
    reason = nil
  end
  local changed = false
  update(path, function(lines)
    local fm = require("logpose.index").frontmatter(lines)
    local from = str(fm.status) or config.get().tasks.capture_status
    local already = M.is_cancelled(from)
    local value = reason or (not none and already and str(fm.cancelled)) or "yes"
    if already and str(fm.cancelled) == value then
      return nil
    end
    changed = true
    lines = M.set_field(lines, "status", config.get().board.cancelled)
    lines = M.set_field(lines, "cancelled", value)
    if str(fm.blocked) then
      lines = M.set_field(lines, "blocked", nil) -- nothing waits on dropped work
    end
    if str(fm.done) then
      lines = M.set_field(lines, "done", nil)
    end
    lines = M.set_field(lines, "order", nil)
    if not already then
      lines = M.append_log(lines, ("%s → %s"):format(M.label(from), M.label(config.get().board.cancelled)))
    end
    if reason then
      lines = M.append_log(lines, "cancelled: " .. reason)
    end
    return lines
  end)
  return changed
end

--- The column a cancelled task left (its log's last `X → Cancelled`), to reopen it there; the
--- capture column when the log doesn't say.
---@param path string
---@return string
function M.reopen_column(path)
  local cancelled = M.label(config.get().board.cancelled)
  local left
  for _, l in ipairs(fs.current_lines(path) or {}) do
    local from, to = l:match("^%- %d%d%d%d%-%d%d%-%d%d %d%d:%d%d: (.-) → (.+)$")
    if from and vim.trim(to) == cancelled then
      left = vim.trim(from)
    end
  end
  for _, c in ipairs(M.columns()) do
    if left and (c.label == left or c.key == left) and c.key ~= config.get().board.done then
      return c.key
    end
  end
  return config.get().tasks.capture_status
end

--- Block (with a reason) or unblock (`reason` nil).
---@param path string
---@param reason? string
function M.set_blocked(path, reason)
  reason = reason and vim.trim(reason) or nil
  if reason == "" then
    reason = "yes"
  end
  update(path, function(lines)
    lines = M.set_field(lines, "blocked", reason)
    return M.append_log(lines, reason and ("blocked: " .. reason) or "unblocked")
  end)
end

--- Move a task to another project (nil: no project), logging the move.
---@param path string
---@param project? string
---@return boolean changed
function M.set_project(path, project)
  local changed = false
  update(path, function(lines)
    local fm = require("logpose.index").frontmatter(lines)
    local old = type(fm.project) == "string" and fm.project ~= "" and fm.project or nil
    if old == project then
      return nil
    end
    changed = true
    lines = M.set_field(lines, "project", project)
    return M.append_log(lines, ("project: %s → %s"):format(old or "none", project or "none"))
  end)
  return changed
end

--- Assign a task to someone (nil or "": nobody), logging the change. Returns whether it changed.
---@param path string
---@param assignee? string
---@return boolean changed
function M.set_assignee(path, assignee)
  assignee = assignee and vim.trim(assignee) or nil
  if assignee == "" then
    assignee = nil
  end
  local changed = false
  update(path, function(lines)
    local fm = require("logpose.index").frontmatter(lines)
    local old = type(fm.assignee) == "string" and str(vim.trim(fm.assignee)) or nil
    if old == assignee then
      return nil
    end
    changed = true
    lines = M.set_field(lines, "assignee", assignee)
    return M.append_log(lines, ("assignee: %s → %s"):format(old or "none", assignee or "none"))
  end)
  return changed
end

---@param path string
---@param order? number
function M.set_order(path, order)
  update(path, function(lines)
    return M.set_field(lines, "order", order)
  end)
end

--- A free `tasks/<slug>.md` path for `title`.
---@param root string
---@param title string
---@return string
function M.path_for(root, title)
  local slug = text.slugify(title)
  if slug == "" then
    slug = "task"
  end
  slug = slug:sub(1, 60):gsub("%-+$", "")
  local dir = M.dir(root)
  -- archived tasks live in `archive/<period>/`, and keep their names
  local taken = function(name)
    return fs.exists(fs.join(dir, name)) or #vim.fn.glob(fs.join(dir, "archive", "*", name), true, true) > 0
  end
  local name, n = slug .. ".md", 2
  while taken(name) do
    name, n = ("%s-%d.md"):format(slug, n), n + 1
  end
  return fs.join(dir, name)
end

--- Take a project out of a task text: `+name` or `project:name` (the last one wins; `+none`
--- means no project). A `+` must start a word and be followed by a letter, so `C++` and `+1`
--- are left alone.
---@param s string
---@return string rest, string|false|nil project false: explicitly none; nil: not given
function M.take_project(s)
  local project
  local function take(lead, name)
    if name:lower() == "none" then
      project = false
    else
      project = require("logpose.project").normalize(name) or project
    end
    return lead
  end
  local rest = (" " .. s):gsub("(%s)%+(%a[%w_%-]*)%f[%s%z]", take):gsub("(%s)project:(%a[%w_%-]*)%f[%s%z]", take)
  return vim.trim(rest), project
end

--- Take people out of a task text. `@name` is the assignee and leaves the text; with
--- `first_only` (a to-do's owner), only the first `@name` counts and the others stay; else the
--- last one wins (`@none`: explicitly nobody). `for:name` adds a stakeholder (repeatable). An `@`
--- must start a word, so e-mail addresses are left alone.
---@param s string
---@param opts? { first_only?: boolean }
---@return string rest, string|false|nil assignee false: explicitly nobody; nil: not given, string[] stakeholders
function M.take_people(s, opts)
  opts = opts or {}
  local assignee
  local stakeholders = {}
  local handle = text.HANDLE
  local taken = false
  local rest = (" " .. s):gsub("(%s)for:(" .. handle .. ")", function(lead, name)
    name = name:gsub("[%.%-]+$", "")
    table.insert(stakeholders, name)
    taken = true
    return lead
  end)
  rest = rest:gsub("([%s%(%[,;])@(" .. handle .. ")", function(lead, name)
    local trail = name:match("[%.%-]+$") or ""
    name = name:sub(1, #name - #trail)
    if opts.first_only and assignee ~= nil then
      return nil -- not the first: a mention, kept
    end
    if name:lower() == "none" then
      assignee = false
    else
      assignee = name
    end
    taken = true
    return lead .. trail
  end)
  if taken then
    rest = rest:gsub("%s+([,;:%.!?])", "%1") -- "ask @ana, then" -> "ask, then"
  end
  rest = rest:gsub("%s+", " ")
  return vim.trim(rest), assignee, stakeholders
end

--- Split a checkbox text into a clean title, its #tags, a `due:` date (`due:2026-10-20`,
--- `due:tomorrow`, `due:+3d`, `due:fri`) and a project (`+acme`, see `M.take_project`). A `due:`
--- that isn't a date stays in the title, and comes back in `unread` (nil when there's none).
---@param s string
---@return string title, string[] tags, string? due, string|false|nil project, string[]? unread
function M.from_text(s)
  local index = require("logpose.index")
  -- A carried-over item ends in "(from [[previous note]])": that link isn't part of the task.
  s = s:gsub("%s*%(from %[%[.-%]%]%)%s*$", ""):gsub("%s*%(from %[.-%]%(.-%)%)%s*$", "")
  local original = s
  local project
  s, project = M.take_project(s)
  local tags = index.tags_in(s)
  local due, unread
  local title = (" " .. s)
    :gsub("(%s)due:(%S+)", function(lead, expr)
      local iso = date.resolve_due(expr)
      if not iso then
        unread = unread or {}
        table.insert(unread, "due:" .. expr)
        return nil -- not a date: keep the text as it is
      end
      due = iso
      return lead
    end)
    :gsub("([%s%(%[,;])#" .. text.TAG, "%1")
    :gsub("%s+", " ")
  title = vim.trim(title)
  if title == "" then
    title = vim.trim(original)
  end
  return title, tags, due, project, unread
end

--- What to say about the `due:` words `M.from_text` couldn't read as dates (nil: nothing).
---@param unread? string[]
---@return string?
function M.due_warning(unread)
  if not unread or #unread == 0 then
    return nil
  end
  local quoted = vim.tbl_map(function(w)
    return "“" .. w .. "”"
  end, unread)
  local one = #unread == 1
  return ("logpose: %s %s, so %s in the title (due: takes a date, today, tomorrow, fri or +3d)"):format(
    table.concat(quoted, ", "),
    one and "isn't a date" or "aren't dates",
    one and "it stayed" or "they stayed"
  )
end

---@class logpose.NewTask
---@field title string
---@field path? string  use this path (from M.path_for) instead of a new one
---@field status? string
---@field project? string
---@field assignee? string
---@field stakeholders? string[]
---@field tags? string[]
---@field due? string
---@field created? string
---@field body? string[] lines placed where the template's {cursor} is

--- Create a task file. Returns its path and the cursor position for editing.
---@param root string
---@param t logpose.NewTask
---@return string path, integer[] cursor
function M.create(root, t)
  local template = require("logpose.template")
  local status = t.status or config.get().tasks.capture_status
  if not M.column_index(status) then
    error(("logpose: unknown board column %q"):format(status), 0)
  end
  local path = t.path or M.path_for(root, t.title)
  local today = date.today()
  local rendered = template.render(
    template.load("task", root),
    template.vars(today, { title = t.title, project = t.project or "", status = M.label(status) })
  )
  local fm = { "---" }
  local values = {
    title = t.title,
    status = status,
    project = t.project,
    assignee = t.assignee,
    stakeholders = t.stakeholders,
    tags = t.tags or {},
    due = t.due,
    blocked = nil,
    -- tasks always know when they were created (the board sorts by it)
    created = t.created or require("logpose.timestamps").now(),
    modified = config.get().timestamps.modified and require("logpose.timestamps").now() or nil,
    started = status == config.get().board.start and today or nil,
    done = status == config.get().board.done and today or nil,
  }
  for _, k in ipairs(M.KEYS) do
    local v = values[k]
    if not (OPTIONAL[k] and (v == nil or v == "" or (type(v) == "table" and #v == 0))) then
      table.insert(fm, require("logpose.frontmatter").line(k, values[k]))
    end
  end
  table.insert(fm, "---")
  local body = vim.split(rendered.text, "\n", { plain = true })
  if body[#body] == "" then
    table.remove(body)
  end
  local row = rendered.cursor[1]
  if t.body and #t.body > 0 then
    -- The given lines go where the cursor would be; the cursor lands on a blank line after them.
    local insert = vim.list_extend(vim.list_extend({}, t.body), { "" })
    if vim.trim(body[row] or "") == "" then
      table.remove(body, row)
    end
    for i, l in ipairs(insert) do
      table.insert(body, row + i - 1, l)
    end
    row = row + #t.body
  end
  local fm_len = #fm
  local lines = vim.list_extend(fm, body)
  lines = M.append_log(lines, "created in " .. M.label(status))
  local text, cursor = require("logpose.markdown").tidy_text(table.concat(lines, "\n"), { row + fm_len, 0 })
  local ok, err = fs.write_file(path, text)
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  return path, cursor
end

return M

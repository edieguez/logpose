--- Task files: one markdown file per task in `dirs.tasks`, with the board column in `status:`.
---
---   ---
---   title: "Fix flaky test"
---   status: in-progress
---   project: acme
---   tags: [perf]
---   due: 2026-10-20
---   blocked: waiting on ana
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
M.KEYS = { "title", "status", "project", "tags", "due", "blocked", "created", "modified", "started", "done", "order" }

---@class logpose.Task
---@field path string
---@field title string
---@field status string
---@field project? string
---@field tags string[]
---@field due? string
---@field blocked? string  reason ("yes" when none was given)
---@field created? string
---@field started? string
---@field done? string
---@field order? number
---@field archived boolean

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
  return i and (config.get().board.columns[i].label or key) or key
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

---@param s string
local function yaml_string(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

---@param key string
---@param value any
---@return string
local function fm_line(key, value)
  if value == nil or value == "" or value == false then
    return key .. ":"
  end
  if key == "title" then
    return "title: " .. yaml_string(value)
  end
  if key == "tags" then
    return "tags: [" .. table.concat(value, ", ") .. "]"
  end
  return key .. ": " .. tostring(value)
end

---@param s any
---@return string?
local function str(s)
  return type(s) == "string" and s ~= "" and s or nil
end

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
  return {
    path = path,
    title = title or vim.fn.fnamemodify(path, ":t:r"),
    status = str(fm.status) or config.get().tasks.capture_status,
    project = str(fm.project) and fm.project:lower() or nil,
    tags = tags,
    due = str(fm.due) and date.is_iso(fm.due) and fm.due or nil,
    blocked = str(fm.blocked),
    created = str(fm.created),
    started = str(fm.started),
    done = str(fm.done),
    order = tonumber(fm.order),
    archived = vim.startswith(fs.normalize(path), fs.normalize(archive)),
  }
end

--- Every task file under `dirs.tasks` (archived ones only with `archived = true`).
---@param root string
---@param opts? { archived?: boolean }
---@return logpose.Task[]
function M.list(root, opts)
  opts = opts or {}
  local dir = M.dir(root)
  local out = {}
  if not fs.is_dir(dir) then
    return out
  end
  for name, kind in vim.fs.dir(dir, { depth = 4 }) do
    if kind == "file" and name:sub(-3) == ".md" then
      local path = fs.join(dir, name)
      local buf = fs.find_buf(path)
      local lines = buf and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or fs.read_lines(path) or {}
      local task = M.parse(path, lines, root)
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
  local new = fm_line(key, value)
  if lines[1] ~= "---" then
    local out = { "---", new, "---" }
    vim.list_extend(out, lines)
    return out
  end
  local close
  for i = 2, #lines do
    if lines[i] == "---" then
      close = i
      break
    end
    if lines[i]:match("^" .. vim.pesc(key) .. ":") then
      if key == "order" and (value == nil or value == "") then
        table.remove(lines, i) -- order only exists while a card is placed by hand
      else
        lines[i] = new
      end
      return lines
    end
  end
  if not close or value == nil or value == "" then
    return lines -- clearing a key that isn't there: nothing to do
  end
  -- Insert before the first known key that comes after `key`, else before the closing ---.
  local rank = {}
  for i, k in ipairs(M.KEYS) do
    rank[k] = i
  end
  local at = close
  for i = 2, close - 1 do
    local k = lines[i]:match("^([%w_%-]+):")
    if k and rank[k] and rank[key] and rank[k] > rank[key] then
      at = i
      break
    end
  end
  table.insert(lines, at, new)
  return lines
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

--- Move a task to `status`, keeping `started`/`done` and the log in step.
---@param path string
---@param status string
---@return boolean changed
function M.set_status(path, status)
  if not M.column_index(status) then
    error(("logpose: unknown board column %q"):format(status), 0)
  end
  local changed = false
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
    return M.append_log(lines, ("%s → %s"):format(M.label(from), M.label(status)))
  end)
  return changed
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
  local path = fs.join(dir, slug .. ".md")
  local n = 2
  while fs.exists(path) or fs.exists(fs.join(dir, "archive", slug .. ".md")) do
    path = fs.join(dir, ("%s-%d.md"):format(slug, n))
    n = n + 1
  end
  return path
end

--- Split a checkbox text into a clean title, its #tags and a `due:` date.
---@param s string
---@return string title, string[] tags, string? due
function M.from_text(s)
  local index = require("logpose.index")
  -- A carried-over item ends in "(from [[previous note]])": that link isn't part of the task.
  s = s:gsub("%s*%(from %[%[.-%]%]%)%s*$", ""):gsub("%s*%(from %[.-%]%(.-%)%)%s*$", "")
  local tags = index.tags_in(s)
  local due = s:match("%f[%w]due:(%d%d%d%d%-%d%d%-%d%d)")
  local title = (" " .. s)
    :gsub("%s+due:%d%d%d%d%-%d%d%-%d%d", "")
    :gsub("([%s%(%[,;])#[%w_][%w_%-/]*", "%1")
    :gsub("%s+", " ")
  title = vim.trim(title)
  if title == "" then
    title = vim.trim(s)
  end
  return title, tags, due and date.is_iso(due) and due or nil
end

---@class logpose.NewTask
---@field title string
---@field path? string  use this path (from M.path_for) instead of a new one
---@field status? string
---@field project? string
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
    if k ~= "order" and not (k == "modified" and values.modified == nil) then
      table.insert(fm, fm_line(k, values[k]))
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

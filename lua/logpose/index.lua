--- Journal index: scans every note into plain items (notes, tasks, tagged lines) that search,
--- action items and reports filter. Pickers only display these items.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local markdown = require("logpose.markdown")

local M = {}

---@class logpose.Item
---@field kind "note"|"task"|"line"
---@field file string
---@field lnum integer
---@field text string
---@field date? string
---@field note_type string  daily|meeting|inbox|done|archive|project|topic|task|other
---@field status? string   task files: board column
---@field blocked? string  task files: block reason
---@field due? string      task files: due date
---@field created? string  task files
---@field started? string  task files
---@field done_date? string task files: when it reached Done
---@field archived? boolean task files under tasks/archive
---@field type? string      meeting type (frontmatter)
---@field project? string
---@field tags string[]     lowercase, without '#'; a note's tags include all its inline tags
---@field fm_tags? string[] notes only: tags from frontmatter
---@field checked? boolean  tasks only
---@field title? string     note title (on every item of that note)
---@field series? string    meeting series (frontmatter; on every item of that note)
---@field section? string   lowercased `## ` heading the item sits under (not date headings)
---@field section_title? string  that heading as written
---@field people string[]   person slugs: @mentions (tasks/lines); attendees, `with:` and all
---                         mentions (notes)
---@field names? table<string, string>  person slug -> name as written (notes only)
---@field links? { target: string, style: "wiki"|"markdown", lnum: integer, text: string }[]
---                         raw outgoing links (notes only; resolved by links.lua)

--- Inline tags in a line: `#word` at the start of a word; not pure numbers.
---@param line string
---@return string[]
function M.tags_in(line)
  local tags = {}
  for tag in (" " .. line):gmatch("[%s%(%[,;]#([%w_][%w_%-/]*)") do
    tag = tag:gsub("[%-/]+$", "")
    if tag ~= "" and not tag:match("^%d+$") then
      table.insert(tags, tag:lower())
    end
  end
  return tags
end

--- @mentions in a line: list of { slug, name }. Must start a word (so e-mails don't count).
---@param line string
---@return { slug: string, name: string }[]
function M.mentions_in(line)
  local out = {}
  for name in (" " .. line):gmatch("[%s%(%[,;]@([%w_][%w_%.%-]*)") do
    name = name:gsub("[%.%-]+$", "")
    local slug = require("logpose.util.text").slugify(name)
    if slug ~= "" then
      table.insert(out, { slug = slug, name = name })
    end
  end
  return out
end

--- Links in a line: wiki `[[target|label]]` and markdown `[label](target)` (local files only).
---@param line string
---@return { target: string, style: "wiki"|"markdown" }[]
function M.links_in(line)
  local out = {}
  for inner in line:gmatch("%[%[(.-)%]%]") do
    local target = vim.trim(inner:match("^([^|]*)") or "")
    target = target:gsub("#.*$", "")
    if target ~= "" then
      table.insert(out, { target = target, style = "wiki" })
    end
  end
  for target in line:gmatch("%]%((.-)%)") do
    target = vim.trim(target):gsub("^<(.*)>$", "%1"):gsub("#.*$", "")
    if target ~= "" and not target:match("^%a[%w+.-]*:") then
      table.insert(out, { target = target, style = "markdown" })
    end
  end
  return out
end

--- Minimal YAML frontmatter: `key: value` scalars and `[a, b]` lists.
---@param lines string[]
---@return table<string, string|string[]> fm, integer body_start (first line after frontmatter)
function M.frontmatter(lines)
  if lines[1] ~= "---" then
    return {}, 1
  end
  local fm = {}
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      return fm, i + 1
    end
    local key, value = line:match("^([%w_%-]+):%s*(.-)%s*$")
    if key then
      local list = value:match("^%[(.*)%]$")
      if list then
        local items = {}
        for v in list:gmatch("[^,]+") do
          v = vim.trim(v):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
          if v ~= "" then
            table.insert(items, v)
          end
        end
        fm[key] = items
      else
        local unquoted = value:match('^"(.*)"$')
        if unquoted then
          value = unquoted:gsub('\\"', '"'):gsub("\\\\", "\\")
        else
          value = value:match("^'(.*)'$") or value
        end
        fm[key] = value
      end
    end
  end
  return {}, 1 -- unterminated: not frontmatter
end

---@param value string|string[]|nil
---@return string[]
local function tag_list(value)
  if type(value) == "table" then
    return vim.tbl_map(function(t)
      return (t:gsub("^#", "")):lower()
    end, value)
  end
  if type(value) == "string" and value ~= "" then
    local out = {}
    for t in value:gmatch("[^,%s]+") do
      table.insert(out, (t:gsub("^#", "")):lower())
    end
    return out
  end
  return {}
end

---@param list string[]
---@return string[]
local function unique(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      table.insert(out, v)
    end
  end
  return out
end

---@param path string
---@param dir string
local function under(path, dir)
  dir = dir:gsub("/+$", "")
  return path == dir or vim.startswith(path, dir .. "/")
end

--- Where a file sits in the journal.
---@param path string
---@param root string
---@return string
function M.note_type(path, root)
  local function p(key)
    return config.path(key, root)
  end
  if path == p("inbox") then
    return "inbox"
  elseif path == p("done") then
    return "done"
  elseif under(path, p("daily")) then
    return "daily"
  elseif under(path, p("meetings")) then
    return "meeting"
  elseif under(path, p("journal_entries")) or under(path, p("done_entries")) then
    return "archive"
  elseif under(path, p("tasks")) then
    return "task"
  elseif under(path, p("projects")) then
    return "project"
  elseif under(path, p("notes")) then
    return "topic"
  end
  return "other"
end

--- Index one file's lines.
---@param path string
---@param lines string[]
---@param root string
---@return logpose.Item[]
function M.index_lines(path, lines, root)
  local items = {}
  local fm, body = M.frontmatter(lines)
  local note_type = M.note_type(path, root)
  local name = vim.fn.fnamemodify(path, ":t:r")

  local title = type(fm.title) == "string" and fm.title ~= "" and fm.title or nil
  if not title then
    for i = body, #lines do
      local h = lines[i]:match("^#%s+(.+)$")
      if h then
        title = vim.trim(h)
        break
      end
    end
  end
  title = title or name

  local note_date = type(fm.date) == "string" and date.is_iso(fm.date) and fm.date or nil
  if not note_date then
    local d = name:match("(%d%d%d%d%-%d%d%-%d%d)")
    note_date = d and date.is_iso(d) and d or nil
  end
  local project = type(fm.project) == "string" and fm.project ~= "" and fm.project:lower() or nil
  local mtype = type(fm.type) == "string" and fm.type ~= "" and fm.type or nil
  local series = type(fm.series) == "string" and fm.series ~= "" and fm.series or nil

  -- People named in frontmatter: attendees (list or comma string) and `with:` (1:1s).
  local names = {}
  local note_people = {}
  local function add_person(name)
    name = vim.trim(name or "")
    local slug = require("logpose.util.text").slugify(name)
    if slug ~= "" then
      names[slug] = names[slug] or name
      table.insert(note_people, slug)
    end
  end
  local attendees = fm.attendees
  if type(attendees) == "string" then
    for n in attendees:gmatch("[^,]+") do
      add_person(n)
    end
  elseif type(attendees) == "table" then
    for _, n in ipairs(attendees) do
      add_person(n)
    end
  end
  if type(fm.with) == "string" then
    add_person(fm.with)
  end

  local note = {
    kind = "note",
    file = path,
    lnum = 1,
    text = title,
    title = title,
    date = note_date,
    note_type = note_type,
    type = mtype,
    series = series,
    project = project,
    tags = tag_list(fm.tags),
    fm_tags = tag_list(fm.tags),
    people = {},
    names = names,
    links = {},
  }
  if note_type == "task" then
    local t = require("logpose.taskfile").parse(path, lines, root)
    note.status, note.blocked, note.due = t.status, t.blocked, t.due
    note.created, note.started, note.done_date, note.archived = t.created, t.started, t.done, t.archived
    note.date = t.done or (t.created and t.created:sub(1, 10)) or note.date
  end
  table.insert(items, note)

  local retrievable = {}
  for _, name in ipairs(config.get().retrieval.sections) do
    retrievable[name:lower()] = true
  end

  local section_date, section, section_title
  local note_tags = vim.list_extend({}, note.tags)
  for i = body, #lines do
    local line = lines[i]
    local is_heading = line:match("^#+%s") ~= nil
    if line:match("^##%s") then
      section_date = markdown.heading_date(line)
      if section_date then
        section, section_title = nil, nil
      else
        section_title = vim.trim((line:gsub("^##%s+", "")))
        section = section_title:lower()
      end
    elseif line:match("^#%s") then
      section, section_title = nil, nil
    end
    local tags = M.tags_in(line)
    vim.list_extend(note_tags, tags)
    for _, l in ipairs(M.links_in(line)) do
      table.insert(note.links, { target = l.target, style = l.style, lnum = i, text = vim.trim(line) })
    end
    local people = {}
    for _, m in ipairs(M.mentions_in(line)) do
      table.insert(people, m.slug)
      names[m.slug] = names[m.slug] or m.name
      table.insert(note_people, m.slug)
    end
    local task = require("logpose.tasks").parse_task(line)
    if task and vim.trim(task.text) == "" then
      task = nil -- empty placeholder from a template ("- [ ] ")
    end
    if task then
      table.insert(items, {
        kind = "task",
        file = path,
        lnum = i,
        text = task.text,
        checked = task.checked,
        date = section_date or note_date,
        note_type = note_type,
        type = mtype,
        series = series,
        project = project,
        tags = tags,
        people = people,
        title = title,
        section = section,
        section_title = section_title,
      })
    elseif
      not is_heading
      and vim.trim(line) ~= ""
      and (#tags > 0 or #people > 0 or (section and retrievable[section]))
    then
      -- Tagged lines, and every line under a retrievable section (Decisions, Blockers…).
      local text = vim.trim(line):gsub("^[-*+]%s+", "")
      table.insert(items, {
        kind = "line",
        file = path,
        lnum = i,
        text = text,
        date = section_date or note_date,
        note_type = note_type,
        type = mtype,
        series = series,
        project = project,
        tags = tags,
        people = people,
        title = title,
        section = section,
        section_title = section_title,
      })
    end
  end
  note.tags = unique(note_tags)
  note.people = unique(note_people)
  return items
end

--- Markdown files under the root, skipping dot-directories and the templates dir.
---@param root string
---@return string[]
function M.files(root)
  local templates = config.path("templates", root)
  local out = {}
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local path = fs.join(dir, name)
      if not name:match("^%.") then
        if kind == "directory" and path ~= templates then
          walk(path)
        elseif (kind == "file" or kind == "link") and name:match("%.md$") then
          table.insert(out, path)
        end
      end
    end
  end
  if fs.is_dir(root) then
    walk(root)
  end
  table.sort(out)
  return out
end

--- Per-file cache: path -> { mtime_sec, mtime_nsec, size, items }. Valid while the options
--- table is the same (setup() resets it) and the file's mtime and size are unchanged.
local cache, cache_opts = {}, nil
M.reads = 0 -- files actually parsed (for tests and health)

--- Bumped whenever logpose writes notes, so cheap consumers (the statusline) know to recompute.
M.generation = 0

function M.clear_cache()
  cache = {}
  M.generation = M.generation + 1
end

--- Build the index for the whole journal.
---@param root string
---@return logpose.Item[]
function M.build(root)
  local opts = config.get()
  if cache_opts ~= opts then
    cache, cache_opts = {}, opts
  end
  local items = {}
  local uv = vim.uv or vim.loop
  local seen = {}
  for _, path in ipairs(M.files(root)) do
    seen[path] = true
    local st = uv.fs_stat(path)
    local hit = st and cache[path]
    if hit and hit.sec == st.mtime.sec and hit.nsec == st.mtime.nsec and hit.size == st.size then
      vim.list_extend(items, hit.items)
    else
      local lines = fs.read_lines(path)
      if lines then
        M.reads = M.reads + 1
        if lines[#lines] == "" then
          table.remove(lines)
        end
        local file_items = M.index_lines(path, lines, root)
        if st then
          cache[path] = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, items = file_items }
        end
        vim.list_extend(items, file_items)
      end
    end
  end
  for path in pairs(cache) do
    if not seen[path] then
      cache[path] = nil
    end
  end
  return items
end

--- Tags with the number of places they appear (tagged tasks/lines, plus notes tagging them in
--- frontmatter), most used first.
---@param items logpose.Item[]
---@return { tag: string, count: integer }[]
function M.tag_counts(items)
  local counts = {}
  for _, item in ipairs(items) do
    local tags = item.kind == "note" and (item.fm_tags or {}) or item.tags
    for _, tag in ipairs(tags) do
      counts[tag] = (counts[tag] or 0) + 1
    end
  end
  local out = {}
  for tag, count in pairs(counts) do
    table.insert(out, { tag = tag, count = count })
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tag < b.tag
  end)
  return out
end

--- People with the number of items involving them (notes, tasks, lines), most first.
---@param items logpose.Item[]
---@return { slug: string, name: string, count: integer }[]
function M.people(items)
  local counts, names = {}, {}
  for _, item in ipairs(items) do
    for slug, name in pairs(item.names or {}) do
      names[slug] = names[slug] or name
    end
    for _, slug in ipairs(item.people or {}) do
      counts[slug] = (counts[slug] or 0) + 1
    end
  end
  local out = {}
  for slug, count in pairs(counts) do
    table.insert(out, { slug = slug, name = names[slug] or slug, count = count })
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.slug < b.slug
  end)
  return out
end

--- Projects seen in the index (frontmatter), sorted.
---@param items logpose.Item[]
---@return string[]
function M.projects(items)
  local seen, out = {}, {}
  for _, item in ipairs(items) do
    if item.project and not seen[item.project] then
      seen[item.project] = true
      table.insert(out, item.project)
    end
  end
  table.sort(out)
  return out
end

return M

--- Journal index: scans every file into plain items that search, the board, action items and
--- reports filter. Pickers only display these items. Four kinds, kept apart:
---   note  a note (daily, meeting, topic note, project page): the whole file
---   task  a task file under `dirs.tasks`: the whole file, with its status, due date…
---   person  a person's page under `dirs.people`: name, aliases, role, contacts, notes
---   todo  a checkbox line (`- [ ] …`) in a note or a task file
---   line  a tagged line, or any line under a retrievable section (Decisions, Blockers…)
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local markdown = require("logpose.markdown")

local M = {}

---@class logpose.Item
---@field kind "note"|"task"|"person"|"todo"|"line"
---@field file string
---@field lnum integer
---@field text string
---@field date? string
---@field file_type string  where the file sits: daily|meeting|project|topic|task|person|other
---@field fields? table     the frontmatter of the file (a line or to-do: of its note), for filters
---@field status? string   tasks: board column
---@field blocked? string  tasks: block reason
---@field due? string      tasks: due date
---@field created? string  tasks
---@field started? string  tasks
---@field done_date? string tasks: when it reached Done
---@field archived? boolean tasks under tasks/archive
---@field type? string      meeting type (frontmatter)
---@field project? string
---@field tags string[]     lowercase, without '#'; a file's tags include all its inline tags
---@field fm_tags? string[] notes and tasks: tags from frontmatter
---@field checked? boolean  to-dos only; also true for a to-do whose task is done
---@field task_link? { target: string, style: string }  to-dos made into tasks: the `→` link
---@field task_link_text? string  that line, trimmed
---@field done_by_task? string  a to-do counted as checked because its task (this file) is done
---@field title? string     the file's title (on every item of that file)
---@field series? string    meeting series (frontmatter; on every item of that note)
---@field section? string   lowercased `## ` heading the item sits under (not date headings)
---@field section_title? string  that heading as written
---@field people string[]   person slugs: @mentions (to-dos/lines); attendees, `with:` and all
---                         mentions (notes and tasks)
---@field names? table<string, string>  person slug -> name as written (notes and tasks)
---@field links? { target: string, style: "wiki"|"markdown", lnum: integer, text: string }[]
---                         raw outgoing links (notes and tasks; resolved by links.lua)
---@field mtime? integer    notes and tasks: when the file was last written (seconds)
---@field related? { file: string, title: string, file_type: string, date?: string, lnum: integer }[]
---                         board cards: notes linked with the task (`links.related`)

--- Inline tags in a line: `#word` at the start of a word; not pure numbers.
---@param line string
---@return string[]
function M.tags_in(line)
  local tags = {}
  for tag in (" " .. line):gmatch("[%s%(%[,;]#(" .. require("logpose.util.text").TAG .. ")") do
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
  for name in (" " .. line):gmatch("[%s%(%[,;]@(" .. require("logpose.util.text").HANDLE .. ")") do
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

--- Items of a flow list's inside (`a, "b, c", 'd'`): commas in quotes don't split, and
--- double-quoted items are unescaped (`frontmatter.quote` in reverse).
---@param s string
---@return string[]
local function list_items(s)
  local items, i = {}, 1
  while true do
    i = s:find("%S", i)
    if not i then
      return items
    end
    local c, v = s:sub(i, i), nil
    if c == '"' then
      local chars, j = {}, i + 1
      while j <= #s and s:sub(j, j) ~= '"' do
        if s:sub(j, j) == "\\" then
          j = j + 1
        end
        table.insert(chars, s:sub(j, j))
        j = j + 1
      end
      v, i = table.concat(chars), j + 1
    elseif c == "'" then
      local j = s:find("'", i + 1, true) or #s + 1
      v, i = s:sub(i + 1, j - 1), j + 1
    else
      local j = s:find(",", i, true) or #s + 1
      v, i = vim.trim(s:sub(i, j - 1)), j
    end
    if v ~= "" then
      table.insert(items, v)
    end
    i = (s:find(",", i, true) or #s) + 1
  end
end

--- Minimal YAML frontmatter: `key: value` scalars and `[a, b]` lists.
---@param lines string[]
---@return table<string, string|string[]> fm, integer body_start (first line after frontmatter)
function M.frontmatter(lines)
  if lines[1] ~= "---" then
    return {}, 1
  end
  local fm = {}
  local block -- the key of an empty value, whose `  - item` lines make a list
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      return fm, i + 1
    end
    local key, value = line:match("^([%w_%-]+):%s*(.-)%s*$")
    local entry = block and line:match("^%s+%-%s+(.-)%s*$")
    block = key and value == "" and key or (entry and block)
    if entry then
      fm[block] = type(fm[block]) == "table" and fm[block] or {}
      entry = entry:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      table.insert(fm[block], entry)
    elseif key then
      local list = value:match("^%[(.*)%]$")
      if list then
        fm[key] = list_items(list)
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
function M.file_type(path, root)
  local function p(key)
    return config.path(key, root)
  end
  if under(path, p("daily")) then
    return "daily"
  elseif under(path, p("meetings")) then
    return "meeting"
  elseif under(path, p("tasks")) then
    return "task"
  elseif under(path, p("people")) then
    return "person"
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
  local file_type = M.file_type(path, root)
  local name = vim.fn.fnamemodify(path, ":t:r")

  local title = type(fm.title) == "string" and fm.title ~= "" and fm.title or nil
  if file_type == "person" and type(fm.name) == "string" and fm.name ~= "" then
    title = fm.name
  end
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
    kind = (file_type == "task" or file_type == "person") and file_type or "note",
    file = path,
    lnum = 1,
    text = title,
    title = title,
    date = note_date,
    file_type = file_type,
    type = mtype,
    series = series,
    project = project,
    tags = tag_list(fm.tags),
    fm_tags = tag_list(fm.tags),
    people = {},
    names = names,
    links = {},
  }
  note.fields = fm -- every frontmatter key, for filters (`role:lead`, `attendees:ana`)
  if file_type == "task" then
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

  -- to-dos made into tasks: the `→ [[task]]` line under them
  local task_links = {}
  for _, t in ipairs(require("logpose.todos").linked(lines)) do
    task_links[t.row] = t
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
    local todo = require("logpose.todos").parse(line)
    if todo and vim.trim(todo.text) == "" then
      todo = nil -- empty placeholder from a template ("- [ ] ")
    end
    if todo then
      table.insert(items, {
        kind = "todo",
        file = path,
        lnum = i,
        text = todo.text,
        checked = todo.checked,
        date = section_date or note_date,
        file_type = file_type,
        type = mtype,
        series = series,
        project = project,
        tags = tags,
        people = people,
        title = title,
        section = section,
        section_title = section_title,
        fields = fm,
        task_link = task_links[i] and task_links[i].link or nil,
        task_link_text = task_links[i] and task_links[i].link_text or nil,
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
        file_type = file_type,
        type = mtype,
        series = series,
        project = project,
        tags = tags,
        people = people,
        title = title,
        section = section,
        section_title = section_title,
        fields = fm,
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

--- Per-file cache: path -> { sec, nsec, size, at, items }. Valid while the options table is
--- the same (setup() resets it) and the file's mtime and size are unchanged.
---
--- An entry is only trusted once it was cached at least two seconds after the file's mtime
--- (`M.fresh`): a file written in the same second as it was read could change again without
--- its mtime moving on filesystems with coarse timestamps, so those are simply read again
--- (git's "racily clean" rule). That's why writes don't have to throw the cache away.
local cache, cache_opts = {}, nil

-- The last build, reused by later builds in the same event-loop tick while nothing was written
-- (`generation` unchanged): one command often builds the index several times (today, standup,
-- reports), and checking every file's timestamp each time is most of the cost.
local memo, memo_pending = nil, false
M.reads = 0 -- files actually parsed (for tests and health)

--- Bumped whenever logpose writes notes, so cheap consumers (the statusline) know to recompute.
M.generation = 0

--- Can a cache entry for a file with this stat be reused?
---@param hit? { sec: integer, nsec: integer, size: integer, at: integer }
---@param st? uv.fs_stat.result
---@return boolean
function M.fresh(hit, st)
  return hit ~= nil
    and st ~= nil
    and hit.sec == st.mtime.sec
    and hit.nsec == st.mtime.nsec
    and hit.size == st.size
    and hit.at >= hit.sec + 2
end

--- Logpose changed notes: tell the statusline and friends. Entries for changed files are
--- revalidated by mtime and size on the next build, so the cache itself is kept.
function M.clear_cache()
  M.generation = M.generation + 1
end

--- Forget the last build, as if a new command started (benchmarks and tests).
function M.forget_build()
  memo = nil
end

--- Drop every cached entry (tests, and when in doubt).
function M.flush()
  cache, memo = {}, nil
  M.generation = M.generation + 1
end

--- A to-do made into a task counts as checked once its task is done, even when the box wasn't
--- ticked (the note was edited outside Neovim, say). Replaces those items with marked copies.
---@param root string
---@param items logpose.Item[]
local function follow_tasks(root, items)
  local tasks, by_name
  local done = config.get().board.done
  for i, it in ipairs(items) do
    if it.kind == "todo" and it.task_link and not it.checked then
      if not tasks then
        tasks, by_name = {}, {}
        for _, t in ipairs(items) do
          if t.kind == "task" then
            tasks[vim.fs.normalize(t.file)] = t
            local stem = vim.fn.fnamemodify(t.file, ":t:r"):lower()
            by_name[stem] = by_name[stem] or {}
            table.insert(by_name[stem], t.file)
          end
        end
      end
      local path = require("logpose.links").resolve(root, it.file, it.task_link, by_name)
      local task = path and tasks[vim.fs.normalize(path)]
      if task and task.status == done then
        items[i] = vim.tbl_extend("force", it, { checked = true, done_by_task = task.file })
      end
    end
  end
end

--- Build the index for the whole journal.
---@param root string
---@return logpose.Item[]
function M.build(root)
  local opts = config.get()
  if cache_opts ~= opts then
    cache, cache_opts = {}, opts
    memo = nil
  end
  if memo and memo.root == root and memo.gen == M.generation then
    return vim.list_extend({}, memo.items) -- a copy: callers may sort or filter the list
  end
  local items = {}
  local uv = vim.uv or vim.loop
  local seen = {}
  for _, path in ipairs(M.files(root)) do
    seen[path] = true
    local st = uv.fs_stat(path)
    local hit = cache[path]
    if M.fresh(hit, st) then
      vim.list_extend(items, hit.items)
    else
      local lines = fs.read_lines(path)
      if lines then
        M.reads = M.reads + 1
        if lines[#lines] == "" then
          table.remove(lines)
        end
        local file_items = M.index_lines(path, lines, root)
        for _, it in ipairs(file_items) do
          if M.is_file(it) then
            it.mtime = st and st.mtime.sec or nil
          end
        end
        if st then
          cache[path] = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, at = os.time(), items = file_items }
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
  follow_tasks(root, items)
  memo = { root = root, gen = M.generation, items = items }
  if not memo_pending then
    memo_pending = true
    vim.schedule(function()
      memo, memo_pending = nil, false
    end)
  end
  return vim.list_extend({}, items)
end

--- Is this item a whole file (a note, a task or a person's page), not a line in one?
---@param it logpose.Item
---@return boolean
function M.is_file(it)
  return it.kind == "note" or it.kind == "task" or it.kind == "person"
end

--- Tags with the number of places they appear (tagged tasks/lines, plus notes tagging them in
--- frontmatter), most used first.
---@param items logpose.Item[]
---@return { tag: string, count: integer }[]
function M.tag_counts(items)
  local counts = {}
  for _, item in ipairs(items) do
    local tags = M.is_file(item) and (item.fm_tags or {}) or item.tags
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

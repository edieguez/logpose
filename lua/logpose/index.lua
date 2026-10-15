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
---@field note_type string  daily|meeting|inbox|done|archive|other
---@field type? string      meeting type (frontmatter)
---@field project? string
---@field tags string[]     lowercase, without '#'; a note's tags include all its inline tags
---@field fm_tags? string[] notes only: tags from frontmatter
---@field checked? boolean  tasks only
---@field title? string     note title (on every item of that note)

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

  local note = {
    kind = "note",
    file = path,
    lnum = 1,
    text = title,
    title = title,
    date = note_date,
    note_type = note_type,
    type = mtype,
    project = project,
    tags = tag_list(fm.tags),
    fm_tags = tag_list(fm.tags),
  }
  table.insert(items, note)

  local section_date
  local note_tags = vim.list_extend({}, note.tags)
  for i = body, #lines do
    local line = lines[i]
    if line:match("^##%s") then
      section_date = markdown.heading_date(line)
    end
    local tags = M.tags_in(line)
    vim.list_extend(note_tags, tags)
    local task = require("logpose.tasks").parse_task(line)
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
        project = project,
        tags = tags,
        title = title,
      })
    elseif #tags > 0 then
      table.insert(items, {
        kind = "line",
        file = path,
        lnum = i,
        text = vim.trim(line),
        date = section_date or note_date,
        note_type = note_type,
        type = mtype,
        project = project,
        tags = tags,
        title = title,
      })
    end
  end
  note.tags = unique(note_tags)
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

--- Build the index for the whole journal.
---@param root string
---@return logpose.Item[]
function M.build(root)
  local items = {}
  for _, path in ipairs(M.files(root)) do
    local lines = fs.read_lines(path)
    if lines then
      if lines[#lines] == "" then
        table.remove(lines)
      end
      vim.list_extend(items, M.index_lines(path, lines, root))
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

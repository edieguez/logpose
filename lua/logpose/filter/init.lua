--- Making the filter language discoverable: what can be typed at each point (with a word on
--- what it does), for the filter bar's menu and command-line completion, and a cheat sheet.
local config = require("logpose.config")

local M = {}

--- The cheat sheet, shown in help windows: { heading } or { example, what it does }.
M.CHEATSHEET = {
  { "Filters" },
  { "word", "the text contains it (accents and case ignored)" },
  { "#perf  tag:perf", "tagged" },
  { "@ana  person:ana", "involves Ana: attendee, 1:1, @mention" },
  { "project:acme", "the project (or a #acme tag)" },
  { "type:retro", "meeting type; or a kind: type:daily, type:topic…" },
  { "open  done  blocked", "tasks and to-dos by state" },
  { "status:in-progress", "tasks in a board column" },
  { "Any frontmatter field" },
  { "attendees:ana", "the field contains it (lists: any item)" },
  { "room:*  has:room", "has the field" },
  { "no:email", "doesn't" },
  { "score>3", "compare numbers: > >= < <=" },
  { "Dates" },
  { "date:2026-10", "a day, a month or a year" },
  { "date>=-7d  due<today", "today, yesterday, -7d, +2w, 2026-10-14" },
  { "date:2026-10-01..2026-10-15", "a range (..2026-09: up to)" },
  { "since:-7d  until:today", "the item's date" },
  { "week:current  sprint:-1", "a whole week or sprint" },
  { "Combining" },
  { "a b", "both (and)" },
  { "a or b", "either; and binds tighter: a b or c = (a b) or c" },
  { "-a  not a", "the opposite: -#draft, not type:daily" },
  { "(a or b) c", "grouping" },
  { 'attendees:"Ana López"', "a value with spaces" },
}

--- The cheat sheet as text lines (for `?` windows).
---@return { [1]: string, [2]?: string }[] lines and their highlight
function M.cheatsheet_lines()
  local out = {}
  local w = 0
  for _, row in ipairs(M.CHEATSHEET) do
    if row[2] then
      w = math.max(w, vim.fn.strdisplaywidth(row[1]))
    end
  end
  for _, row in ipairs(M.CHEATSHEET) do
    if row[2] then
      table.insert(out, { ("  %s%s  %s"):format(row[1], string.rep(" ", w - vim.fn.strdisplaywidth(row[1])), row[2]) })
    else
      if #out > 0 then
        table.insert(out, { "" })
      end
      table.insert(out, { row[1], "Title" })
    end
  end
  return out
end

--- Filters you can start a word with, and what they do.
local KEYS = {
  { "type:", "meeting type, or kind of note (daily, topic…)" },
  { "project:", "a project" },
  { "#", "a tag" },
  { "@", "a person" },
  { "attendees:", "meetings with a person" },
  { "with:", "1:1s with a person" },
  { "date:", "a day, month, year or range" },
  { "date>=", "on or after a date" },
  { "date<=", "on or before a date" },
  { "since:", "from a date" },
  { "until:", "up to a date" },
  { "week:", "a whole week" },
  { "sprint:", "a whole sprint" },
  { "due<", "tasks due before" },
  { "status:", "tasks in a board column" },
  { "open", "unfinished tasks and to-dos" },
  { "done", "finished tasks and to-dos" },
  { "blocked", "blocked tasks" },
  { "section:", "lines under a heading" },
  { "has:", "has a field" },
  { "no:", "lacks a field" },
  { "or", "either the filter before or after" },
  { "not", "the opposite of the next filter" },
}

local DATE_KEYS = {
  date = true,
  due = true,
  created = true,
  modified = true,
  started = true,
  done = true,
  since = true,
  ["until"] = true,
}

--- Values for a date: words with what they mean today.
---@return { [1]: string, [2]: string }[]
local function dates()
  local date = require("logpose.util.date")
  local today = date.today()
  local month = today:sub(1, 7)
  local y, m = tonumber(today:sub(1, 4)), tonumber(today:sub(6, 7))
  local prev = m == 1 and ("%d-12"):format(y - 1) or ("%d-%02d"):format(y, m - 1)
  return {
    { "today", today },
    { "yesterday", date.add_days(today, -1) },
    { "-7d", "a week ago: " .. date.add_days(today, -7) },
    { "-30d", "30 days ago: " .. date.add_days(today, -30) },
    { "+7d", "in a week: " .. date.add_days(today, 7) },
    { month, "this month" },
    { prev, "last month" },
    { today:sub(1, 4), "this year" },
    { date.add_days(today, -14) .. ".." .. today, "a range: from..to" },
  }
end

--- Frontmatter keys used in the journal, most used first.
---@param items logpose.Item[]
---@return string[]
local function field_keys(items)
  local index = require("logpose.index")
  local counts = {}
  for _, it in ipairs(items) do
    if index.is_file(it) then
      for k in pairs(it.fields or {}) do
        counts[k] = (counts[k] or 0) + 1
      end
    end
  end
  local out = vim.tbl_keys(counts)
  table.sort(out, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  return out
end

--- The values a field takes, most used first.
---@param items logpose.Item[]
---@param key string
---@return string[]
local function field_values(items, key)
  local index = require("logpose.index")
  local counts = {}
  for _, it in ipairs(items) do
    if index.is_file(it) then
      local v = (it.fields or {})[key]
      for _, x in ipairs(type(v) == "table" and v or { v }) do
        if type(x) == "string" and x ~= "" and #x < 60 then
          counts[x] = (counts[x] or 0) + 1
        end
      end
    end
  end
  local out = vim.tbl_keys(counts)
  table.sort(out, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  return out
end

--- A value as typed: quoted when it has spaces.
---@param v string
---@return string
local function typed(v)
  return v:find("%s") and ('"' .. v .. '"') or v
end

--- What can be typed for `token` (the word being typed): { word, abbr, menu } items, best first.
---@param token string
---@param root? string
---@return { word: string, abbr: string, menu: string }[]
function M.complete(token, root)
  root = root or config.resolve_root()
  local plain = function(s)
    return require("logpose.people").plain(s)
  end
  local neg = token:match("^%-") and "-" or ""
  local t = token:sub(#neg + 1)
  local out = {}
  local function add(word, menu, abbr)
    table.insert(out, { word = neg .. word, abbr = abbr or word, menu = menu or "" })
  end
  local function starts(s, prefix)
    return prefix == "" or vim.startswith(plain(s), plain(prefix))
  end
  local items = root and require("logpose.index").build(root) or {}

  local key, op, value = t:match("^([%a_][%w_%-]*)([:<>]=?)(.*)$")
  if t:match("^#") then
    key, op, value = "tag", "#", t:sub(2)
  elseif t:match("^@") then
    key, op, value = "person", "@", t:sub(2)
  end
  if not key then
    for _, k in ipairs(KEYS) do
      if starts(k[1], t) then
        add(k[1], k[2])
      end
    end
    local seen = {}
    for _, k in ipairs(KEYS) do
      seen[k[1]:match("^([%a_]+)") or k[1]] = true
    end
    for _, k in ipairs(field_keys(items)) do
      if not seen[k] and starts(k, t) then
        add(k .. ":", "a field of your notes")
      end
    end
    return out
  end
  key = key:lower()
  local prefix = op == "#" and "#" or op == "@" and "@" or (key .. op)

  if key == "project" or key == "p" then
    if root then
      local project = require("logpose.project")
      for _, name in ipairs(require("logpose.search").projects(root, items)) do
        if starts(name, value) then
          local title = project.title(root, name)
          add(prefix .. name, title ~= name and title or "project")
        end
      end
    end
  elseif key == "tag" then
    for _, c in ipairs(require("logpose.index").tag_counts(items)) do
      if starts(c.tag, value) then
        add((op == "#" and "#" or prefix) .. c.tag, ("%d"):format(c.count))
      end
    end
  elseif key == "person" or key == "attendees" or key == "with" then
    local people = require("logpose.people")
    for _, p in ipairs(people.match(people.known(root), value)) do
      add(prefix .. p.slug, p.name .. (p.role and (" · " .. p.role) or ""), prefix .. p.name)
    end
  elseif key == "type" then
    for _, mt in ipairs(require("logpose.notes.meeting").types()) do
      if starts(mt.key, value) then
        add(prefix .. mt.key, mt.spec.label or "meeting type")
      end
    end
    for _, k in ipairs({
      { "meeting", "every meeting" },
      { "daily", "daily notes" },
      { "topic", "topic notes" },
      { "project", "project pages" },
      { "task", "tasks" },
      { "person", "people's pages" },
    }) do
      if starts(k[1], value) then
        add(prefix .. k[1], k[2])
      end
    end
  elseif key == "status" then
    for _, c in ipairs(require("logpose.taskfile").columns()) do
      if starts(c.key, value) then
        add(prefix .. c.key, c.label)
      end
    end
  elseif key == "week" or key == "sprint" then
    for _, v in ipairs({ { "current", "this " .. key }, { "-1", "the last one" }, { "+1", "the next one" } }) do
      if starts(v[1], value) then
        add(prefix .. v[1], v[2])
      end
    end
  elseif key == "section" then
    for _, name in ipairs(config.get().retrieval.sections) do
      local v = name:gsub("%s", "-")
      if starts(v, value) then
        add(prefix .. v, "lines under ## " .. name)
      end
    end
  elseif key == "has" or key == "no" then
    for _, k in ipairs(field_keys(items)) do
      if starts(k, value) then
        add(prefix .. k, key == "has" and "has it" or "doesn't have it")
      end
    end
  elseif DATE_KEYS[key] then
    for _, d in ipairs(dates()) do
      if starts(d[1], value) then
        add(prefix .. d[1], d[2])
      end
    end
  else
    for _, v in ipairs(field_values(items, key)) do
      if starts(v, value) or (value ~= "" and plain(v):find(plain(value), 1, true)) then
        add(prefix .. typed(v), key)
      end
      if #out >= 30 then
        break
      end
    end
    if op == ":" and value == "" then
      add(prefix .. "*", "has any " .. key)
    end
  end
  return out
end

return M

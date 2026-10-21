--- The filter language for `:Logpose find`, the board's and the lists' `/`, reports and actions.
--- Filters are ANDed; `or`, `not` (or a leading `-`) and parentheses combine them:
---   project:acme  p:acme   item's project, or a #acme tag
---   #perf  tag:perf        tagged
---   type:retro             meeting type, or the kind of note: daily, meeting, topic, project,
---                          task, person
---   open | done            tasks (Done or not) and to-dos (checked or not)
---   since:DATE  until:DATE   DATE = YYYY-MM-DD, today, yesterday, -7d, +2w…
---   week:SPEC  sprint:SPEC   SPEC = current, -1, +1, a date, or a sprint number
---   section:decisions      under a `## ` heading containing the text
---   person:ana  @ana       involves the person (attendee, 1:1, @mention), under any of their names
---   status:todo  blocked   tasks: board column; blocked tasks
---   any frontmatter field  attendees:ana  role:lead  date:2026-10  date>=-7d  due<today
---                          date:2026-10-01..2026-10-15  slack:*  has:email  no:email
---   anything else          words that must all appear in the text (accents ignored)
local date = require("logpose.util.date")

local M = {}

---@class logpose.Query
---@field expr table  the parsed expression ({ op = "and"|"or"|"not"|"true"|"atom", … })

--- Lowercase without accents (people's names, words).
---@param s string
---@return string
local function plain(s)
  return require("logpose.people").plain(s)
end

--- Fields holding dates, and where an item keeps them.
local DATE_FIELDS = {
  date = "date",
  due = "due",
  done = "done_date",
  created = "created",
  started = "started",
  modified = false, -- frontmatter only
}

--- Fields holding people.
local PEOPLE_FIELDS = { attendees = true, with = true }

--- The first and last day of a full or partial date ("2026", "2026-10", "2026-10-14"), or of a
--- relative one (today, -7d…).
---@param s string
---@param today string
---@return string? first, string? last
local function day_range(s, today)
  local iso = date.resolve(s, today)
  if iso then
    return iso, iso
  end
  local y, m = s:match("^(%d%d%d%d)%-(%d%d)$")
  if y then
    local month = tonumber(m)
    if month < 1 or month > 12 then
      return nil
    end
    local last = os.date("%d", os.time({ year = tonumber(y), month = month + 1, day = 0, hour = 12 })) --[[@as string]]
    return ("%s-%s-01"):format(y, m), ("%s-%s-%s"):format(y, m, last)
  end
  y = s:match("^(%d%d%d%d)$")
  if y then
    return y .. "-01-01", y .. "-12-31"
  end
  return nil
end

--- Does a value look like a date (full, partial or relative)?
---@param s string
---@param today string
---@return boolean
local function is_date(s, today)
  return day_range(s, today) ~= nil
end

--- Tokens of a typed query: words, `(`, `)`, with "quoted text" kept together.
---@param text string
---@return string[]
local function tokenize(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == "(" or c == ")" then
      table.insert(out, c)
      i = i + 1
    else
      local buf, quoted = {}, false
      while i <= n do
        c = text:sub(i, i)
        if c == '"' then
          quoted = not quoted
        elseif not quoted and (c:match("%s") or c == "(" or c == ")") then
          break
        else
          table.insert(buf, c)
        end
        i = i + 1
      end
      table.insert(out, table.concat(buf))
    end
  end
  return out
end

--- Split a typed query into arguments.
---@param text string
---@return string[]
function M.split(text)
  return tokenize(vim.trim(text or ""))
end

---@param list any
---@return any[]
local function as_list(list)
  if type(list) == "table" then
    return list
  end
  if list == nil or list == "" then
    return {}
  end
  return { list }
end

--- The values of `key` on an item (a list; empty when it has none).
---@param it logpose.Item
---@param key string
---@return any[]
local function values_of(it, key)
  local slot = DATE_FIELDS[key]
  if slot then
    local v = it[slot]
    if v ~= nil and v ~= "" then
      return { v }
    end
  end
  if key == "title" then
    return { it.title or it.text }
  elseif key == "text" then
    return { it.text }
  elseif key == "status" then
    return { it.status }
  elseif key == "project" then
    return { it.project }
  elseif key == "tags" or key == "tag" then
    return it.tags or {}
  end
  return as_list((it.fields or {})[key])
end

--- Compare one value with the filter.
---@param v any
---@param op string ":"|">="|">"|"<="|"<"
---@param want string
---@param want_date? { first: string, last: string, from?: string, to?: string }
---@return boolean
local function compare(v, op, want, want_date)
  v = tostring(v)
  if want_date then
    local d = v:match("^(%d%d%d%d%-%d%d%-%d%d)")
    if not d then
      return false
    end
    if want_date.from then -- a range
      return d >= want_date.from and d <= want_date.to
    elseif op == ":" then
      return d >= want_date.first and d <= want_date.last
    elseif op == ">=" then
      return d >= want_date.first
    elseif op == ">" then
      return d > want_date.last
    elseif op == "<=" then
      return d <= want_date.last
    else
      return d < want_date.first
    end
  end
  local a, b = tonumber(v), tonumber(want)
  if a and b and op ~= ":" then
    if op == ">=" then
      return a >= b
    elseif op == ">" then
      return a > b
    elseif op == "<=" then
      return a <= b
    end
    return a < b
  end
  if op == ":" then
    return plain(v):find(plain(want), 1, true) ~= nil
  end
  local pv, pw = plain(v), plain(want)
  if op == ">=" then
    return pv >= pw
  elseif op == ">" then
    return pv > pw
  elseif op == "<=" then
    return pv <= pw
  end
  return pv < pw
end

--- Every slug that means the person `name` (their page's name and aliases).
---@param name string
---@return table<string, boolean>
local function person_slugs(name)
  local slug = require("logpose.util.text").slugify((name:gsub("^@", "")))
  local ok, set = pcall(require("logpose.people").expand, slug)
  return ok and set or { [slug] = true }
end

--- Build the predicate for one filter. Errors (raised) for invalid values.
---@param arg string
---@param today string
---@return table node
local function atom(arg, today)
  local key, op, value = arg:match("^([%a_][%w_%-]*)(>=)(.*)$")
  if not key then
    key, op, value = arg:match("^([%a_][%w_%-]*)(<=)(.*)$")
  end
  if not key then
    key, op, value = arg:match("^([%a_][%w_%-]*)([:<>])(.*)$")
  end
  key = key and key:lower()
  local function node(fn)
    return { op = "atom", fn = fn, text = arg }
  end

  if key and value == "" then
    error(("logpose: %s needs a value"):format(key .. op), 0)
  end
  if not key then
    if arg:match("^@.") then
      local set
      return node(function(it)
        set = set or person_slugs(arg)
        for _, slug in ipairs(it.people or {}) do
          if set[slug] then
            return true
          end
        end
        return false
      end)
    elseif arg:match("^#.") then
      local tag = arg:sub(2):lower()
      return node(function(it)
        return vim.tbl_contains(it.tags or {}, tag)
      end)
    elseif arg == "open" or arg == "done" then
      return node(function(it)
        local done
        if it.kind == "task" then
          done = it.status == require("logpose.config").get().board.done
        elseif it.kind == "todo" then
          done = it.checked
        else
          return false
        end
        return done == (arg == "done")
      end)
    elseif arg == "blocked" then
      return node(function(it)
        return it.kind == "task" and it.blocked ~= nil and it.blocked ~= false
      end)
    elseif arg == "@" or arg == "#" or arg:match("^%-*$") then
      error(("logpose: %q needs a name"):format(arg), 0)
    end
    local word = plain(arg)
    return node(function(it)
      return plain(it.text .. " " .. (it.title or "")):find(word, 1, true) ~= nil
    end)
  end

  if op == ":" then
    if key == "project" or key == "p" then
      local p = value:lower()
      return node(function(it)
        return it.project == p or vim.tbl_contains(it.tags or {}, p)
      end)
    elseif key == "tag" then
      local tag = value:gsub("^#", ""):lower()
      return node(function(it)
        return vim.tbl_contains(it.tags or {}, tag)
      end)
    elseif key == "type" then
      local t = value:lower()
      return node(function(it)
        return (it.type and it.type:lower() == t) or it.file_type == t or (t == "note" and it.kind == "note")
      end)
    elseif key == "since" or key == "until" then
      local d = date.resolve(value, today)
      if not d then
        error(("logpose: %s: needs a date (YYYY-MM-DD, today, -7d…), got %q"):format(key, value), 0)
      end
      return node(function(it)
        if not it.date then
          return false
        end
        return key == "since" and it.date >= d or (key == "until" and it.date <= d)
      end)
    elseif key == "week" or key == "sprint" then
      local p, err = require("logpose.period").resolve(key, value, today)
      if not p then
        error(err, 0)
      end
      return node(function(it)
        return it.date ~= nil and it.date >= p.start and it.date <= p.finish
      end)
    elseif key == "section" then
      local section = (value:lower():gsub("%-", " "))
      return node(function(it)
        return it.section ~= nil and it.section:find(section, 1, true) ~= nil
      end)
    elseif key == "person" then
      local set
      return node(function(it)
        set = set or person_slugs(value)
        for _, slug in ipairs(it.people or {}) do
          if set[slug] then
            return true
          end
        end
        return false
      end)
    elseif key == "status" then
      local s = value:lower()
      return node(function(it)
        if it.kind ~= "task" or not it.status then
          return false
        end
        return it.status == s or plain(require("logpose.taskfile").label(it.status)) == plain(value)
      end)
    elseif key == "has" or key == "no" then
      local field = value:lower()
      return node(function(it)
        local has = false
        for _, v in ipairs(values_of(it, field)) do
          has = has or (v ~= "" and v ~= false)
        end
        return has == (key == "has")
      end)
    end
  end

  -- any field: people, dates, numbers, text
  if PEOPLE_FIELDS[key] then
    if op ~= ":" then
      error(("logpose: %s compares with :, not %s"):format(key, op), 0)
    end
    local set
    local want = plain(value)
    return node(function(it)
      set = set or person_slugs(value)
      local slugify = require("logpose.util.text").slugify
      for _, v in ipairs(values_of(it, key)) do
        if type(v) == "string" and (set[slugify(v)] or plain(v):find(want, 1, true)) then
          return true
        end
      end
      return false
    end)
  end
  if value == "*" then
    return node(function(it)
      for _, v in ipairs(values_of(it, key)) do
        if v ~= "" and v ~= false then
          return true
        end
      end
      return false
    end)
  end
  local want_date
  local from, to = value:match("^(.-)%.%.(.+)$")
  if from and op == ":" then
    local f = from ~= "" and day_range(from, today) or "0000-01-01"
    local _, t = day_range(to, today)
    if not f or not t then
      error(("logpose: %s: needs a range of dates, like 2026-10-01..2026-10-15"):format(key), 0)
    end
    want_date = { from = f, to = t }
  elseif DATE_FIELDS[key] ~= nil or is_date(value, today) then
    local first, last = day_range(value, today)
    if not first then
      error(("logpose: %s: needs a date (YYYY-MM-DD, 2026-10, today, -7d…), got %q"):format(key, value), 0)
    end
    want_date = { first = first, last = last }
  end
  return node(function(it)
    for _, v in ipairs(values_of(it, key)) do
      if v ~= "" and compare(v, op, value, want_date) then
        return true
      end
    end
    return false
  end)
end

--- Parse filters into a query. `lenient` (while typing) skips what's invalid or half-typed
--- instead of raising, and closes open parentheses.
---@param args string[]
---@param today? string defaults to today
---@param lenient? boolean
---@return logpose.Query q, string[] skipped
function M.parse(args, today, lenient)
  today = today or date.today()
  local tokens = tokenize(table.concat(args or {}, " "))
  local skipped = {}
  local pos = 1
  local TRUE = { op = "true" }

  local function peek()
    return tokens[pos]
  end
  local function is_word(t, ...)
    if not t then
      return false
    end
    local l = t:lower()
    for _, w in ipairs({ ... }) do
      if l == w then
        return true
      end
    end
    return false
  end

  local expr, term, factor

  function factor()
    local t = peek()
    if t == nil then
      return nil
    end
    if is_word(t, "not", "!") then
      pos = pos + 1
      local f = factor()
      return f and { op = "not", arg = f } or nil
    end
    if t == "(" then
      pos = pos + 1
      local e = expr()
      if peek() == ")" then
        pos = pos + 1
      elseif not lenient then
        error("logpose: a ( without its )", 0)
      end
      return e or TRUE
    end
    if t == ")" then
      if not lenient then
        error("logpose: a ) without its (", 0)
      end
      pos = pos + 1
      table.insert(skipped, t)
      return TRUE
    end
    pos = pos + 1
    local negate = false
    if t:match("^%-[^%d%s]") then
      negate, t = true, t:sub(2)
    end
    local ok, res = pcall(atom, t, today)
    if not ok then
      if not lenient then
        error(res, 0)
      end
      table.insert(skipped, t)
      return TRUE
    end
    return negate and { op = "not", arg = res } or res
  end

  function term()
    local parts = {}
    while true do
      local t = peek()
      if t == nil or t == ")" and #parts > 0 or is_word(t, "or", "|") then
        break
      end
      if is_word(t, "and", "&") then
        pos = pos + 1
      else
        local f = factor()
        if f then
          table.insert(parts, f)
        end
      end
    end
    if #parts == 0 then
      return nil
    end
    return #parts == 1 and parts[1] or { op = "and", args = parts }
  end

  function expr()
    local parts = {}
    local t = term()
    if t then
      table.insert(parts, t)
    end
    while is_word(peek(), "or", "|") do
      pos = pos + 1
      t = term()
      if t then
        table.insert(parts, t)
      elseif not lenient then
        error("logpose: `or` needs a filter after it", 0)
      end
    end
    if #parts == 0 then
      return nil
    end
    return #parts == 1 and parts[1] or { op = "or", args = parts }
  end

  local e = expr()
  while pos <= #tokens do -- a stray `)` at the top level
    if not lenient then
      error("logpose: a ) without its (", 0)
    end
    table.insert(skipped, tokens[pos])
    pos = pos + 1
    local more = expr()
    if more then
      e = e and { op = "and", args = { e, more } } or more
    end
  end
  return { expr = e or TRUE }, skipped
end

---@param node table
---@param it logpose.Item
---@return boolean
local function eval(node, it)
  local op = node.op
  if op == "atom" then
    return node.fn(it) and true or false
  elseif op == "and" then
    for _, a in ipairs(node.args) do
      if not eval(a, it) then
        return false
      end
    end
    return true
  elseif op == "or" then
    for _, a in ipairs(node.args) do
      if eval(a, it) then
        return true
      end
    end
    return false
  elseif op == "not" then
    return not eval(node.arg, it)
  end
  return true
end

---@param item logpose.Item
---@param q logpose.Query
---@return boolean
function M.match(item, q)
  return eval(q.expr, item)
end

---@param items logpose.Item[]
---@param q logpose.Query
---@return logpose.Item[]
function M.filter(items, q)
  return vim.tbl_filter(function(item)
    return M.match(item, q)
  end, items)
end

--- Does the query filter anything?
---@param q logpose.Query
---@return boolean
function M.is_empty(q)
  return q.expr.op == "true"
end

return M

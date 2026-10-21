--- Filter language for `:Logpose find`: all filters are ANDed.
---   project:acme  p:acme   item's project, or a #acme tag
---   #perf  tag:perf        tagged
---   type:retro             meeting type
---   open | done            tasks (Done or not) and to-dos (checked or not)
---   since:DATE  until:DATE   DATE = YYYY-MM-DD, today, yesterday, -7d, +2w…
---   week:SPEC  sprint:SPEC   SPEC = current, -1, +1, a date, or a sprint number
---   section:decisions      under a `## ` heading containing the text
---   person:ana  @ana       involves the person (attendee, 1:1, @mention)
---   status:todo  blocked   tasks: board column; blocked tasks
---   anything else          words that must all appear in the text
local date = require("logpose.util.date")

local M = {}

---@class logpose.Query
---@field project? string
---@field tags string[]
---@field type? string
---@field state? "open"|"done"
---@field since? string
---@field until? string
---@field section? string
---@field people string[]
---@field status? string
---@field blocked? boolean
---@field words string[]

---@param args string[]
---@param today? string defaults to today
---@param lenient? boolean skip invalid or half-typed filters instead of raising (live search)
---@return logpose.Query q, string[] skipped
function M.parse(args, today, lenient)
  today = today or date.today()
  local q = { tags = {}, words = {}, people = {} }
  local skipped = {}
  local function fail(msg)
    if not lenient then
      error(msg, 0)
    end
    table.insert(skipped, msg)
  end
  for _, arg in ipairs(args) do
    local key, value = arg:match("^(%a+):(.+)$")
    key = key and key:lower()
    if lenient and (arg:match("^%a+:$") or arg == "#" or arg == "@") then
      -- still typing: `project:`, `#`, `@`
      table.insert(skipped, arg)
    elseif key == "project" or key == "p" then
      q.project = value:lower()
    elseif key == "tag" then
      table.insert(q.tags, (value:gsub("^#", "")):lower())
    elseif key == "type" then
      q.type = value
    elseif key == "since" or key == "until" then
      local d = date.resolve(value, today)
      if not d then
        fail(("logpose: %s: needs a date (YYYY-MM-DD, today, -7d…), got %q"):format(key, value))
      else
        q[key] = d
      end
    elseif key == "week" or key == "sprint" then
      local p, err = require("logpose.period").resolve(key, value, today)
      if not p then
        fail(err)
      else
        q.since, q["until"] = p.start, p.finish
      end
    elseif key == "person" then
      table.insert(q.people, require("logpose.util.text").slugify(value))
    elseif key == "status" then
      q.status = value:lower()
    elseif key == "section" then
      q.section = (value:lower():gsub("%-", " "))
    elseif arg:match("^@.") then
      table.insert(q.people, require("logpose.util.text").slugify(arg:sub(2)))
    elseif arg:match("^#.") then
      table.insert(q.tags, arg:sub(2):lower())
    elseif arg == "open" or arg == "done" then
      q.state = arg
    elseif arg == "blocked" then
      q.blocked = true
    else
      table.insert(q.words, arg:lower())
    end
  end
  return q, skipped
end

--- Split a typed query into arguments.
---@param text string
---@return string[]
function M.split(text)
  return vim.split(vim.trim(text or ""), "%s+", { trimempty = true })
end

---@param list string[]
---@param value string
local function has(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

---@param item logpose.Item
---@param q logpose.Query
---@return boolean
function M.match(item, q)
  if q.project and item.project ~= q.project and not has(item.tags, q.project) then
    return false
  end
  for _, tag in ipairs(q.tags) do
    if not has(item.tags, tag) then
      return false
    end
  end
  if #q.people > 0 then
    -- a person under any of their names (a page's name and aliases), worked out once per query
    q._people = q._people
      or vim.tbl_map(function(person)
        local ok, set = pcall(require("logpose.people").expand, person)
        return ok and set or { [person] = true }
      end, q.people)
    for _, set in ipairs(q._people) do
      local found = false
      for _, slug in ipairs(item.people or {}) do
        found = found or set[slug] == true
      end
      if not found then
        return false
      end
    end
  end
  if q.type and item.type ~= q.type then
    return false
  end
  if q.state then
    local done
    if item.kind == "task" then
      done = item.status == require("logpose.config").get().board.done
    elseif item.kind == "todo" then
      done = item.checked
    else
      return false
    end
    if done ~= (q.state == "done") then
      return false
    end
  end
  if q.status and not (item.kind == "task" and item.status == q.status) then
    return false
  end
  if q.blocked and not (item.kind == "task" and item.blocked) then
    return false
  end
  if q.since and (not item.date or item.date < q.since) then
    return false
  end
  if q["until"] and (not item.date or item.date > q["until"]) then
    return false
  end
  if q.section and not (item.section and item.section:find(q.section, 1, true)) then
    return false
  end
  if #q.words > 0 then
    local hay = (item.text .. " " .. (item.title or "")):lower()
    for _, w in ipairs(q.words) do
      if not hay:find(w, 1, true) then
        return false
      end
    end
  end
  return true
end

---@param items logpose.Item[]
---@param q logpose.Query
---@return logpose.Item[]
function M.filter(items, q)
  return vim.tbl_filter(function(item)
    return M.match(item, q)
  end, items)
end

return M

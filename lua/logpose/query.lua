--- Filter language for `:Logpose find`: all filters are ANDed.
---   project:acme  p:acme   item's project, or a #acme tag
---   #perf  tag:perf        tagged
---   type:retro             meeting type
---   open | done            tasks by state
---   since:YYYY-MM-DD  until:YYYY-MM-DD
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
---@field words string[]

---@param args string[]
---@return logpose.Query
function M.parse(args)
  local q = { tags = {}, words = {} }
  for _, arg in ipairs(args) do
    local key, value = arg:match("^(%a+):(.+)$")
    key = key and key:lower()
    if key == "project" or key == "p" then
      q.project = value:lower()
    elseif key == "tag" then
      table.insert(q.tags, (value:gsub("^#", "")):lower())
    elseif key == "type" then
      q.type = value
    elseif key == "since" or key == "until" then
      if not date.is_iso(value) then
        error(("logpose: %s: needs a YYYY-MM-DD date, got %q"):format(key, value), 0)
      end
      q[key] = value
    elseif arg:match("^#.") then
      table.insert(q.tags, arg:sub(2):lower())
    elseif arg == "open" or arg == "done" then
      q.state = arg
    else
      table.insert(q.words, arg:lower())
    end
  end
  return q
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
  if q.type and item.type ~= q.type then
    return false
  end
  if q.state then
    if item.kind ~= "task" or item.checked ~= (q.state == "done") then
      return false
    end
  end
  if q.since and (not item.date or item.date < q.since) then
    return false
  end
  if q["until"] and (not item.date or item.date > q["until"]) then
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

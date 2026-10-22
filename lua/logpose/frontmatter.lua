--- Writing YAML frontmatter, in one place: how values are written (quoting when YAML needs it),
--- and setting or removing keys in a note's lines without touching anything else. Reading is
--- `index.frontmatter` (values) and `M.read` (keys in order).
local M = {}

--- A string in double quotes, escaped.
---@param s string
---@return string
function M.quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- Does a plain value need quotes to stay a string in YAML?
---@param s string
---@return boolean
local function needs_quotes(s)
  return s:find(": ") ~= nil
    or s:find(" #") ~= nil
    or s:find("^[%[{&*!|>'\"%%@`#,%-?:]") ~= nil
    or s:find("%s$") ~= nil
    or s:find("^%s") ~= nil
end

--- A list item: quoted when it holds something YAML would read otherwise.
---@param s string
---@return string
local function item(s)
  return (s:find("[,:%[%]\"'#{}]") or needs_quotes(s)) and M.quote(s) or s
end

--- A value as it goes after `key: ` ("" for an empty value).
---@param key string
---@param value string|number|boolean|string[]|nil
---@return string
function M.render(key, value)
  if value == nil or value == false then
    return ""
  end
  if type(value) == "table" then
    return "[" .. table.concat(vim.tbl_map(item, value), ", ") .. "]"
  end
  if type(value) ~= "string" then
    return tostring(value)
  end
  if value == "" then
    return ""
  end
  if key == "title" or needs_quotes(value) then
    return M.quote(value)
  end
  return value
end

--- One frontmatter line: `key: value`, or `key:` when empty.
---@param key string
---@param value string|number|boolean|string[]|nil
---@return string
function M.line(key, value)
  local v = M.render(key, value)
  return v == "" and (key .. ":") or (key .. ": " .. v)
end

--- The line of the closing `---` (nil without frontmatter).
---@param lines string[]
---@return integer?
function M.close(lines)
  if lines[1] ~= "---" then
    return nil
  end
  for i = 2, #lines do
    if lines[i] == "---" then
      return i
    end
  end
  return nil
end

---@class logpose.FmEntry
---@field key string
---@field value string|string[]  as read (lists split, quotes removed)

--- The frontmatter's keys in order, with their values, and the line of its closing `---`.
---@param lines string[]
---@return logpose.FmEntry[], integer?
function M.read(lines)
  local close = M.close(lines)
  if not close then
    return {}, nil
  end
  local fm = require("logpose.index").frontmatter(vim.list_slice(lines, 1, close))
  local entries = {}
  for j = 2, close - 1 do
    local key = lines[j]:match("^([%w_%-]+):")
    if key then
      table.insert(entries, { key = key, value = fm[key] or "" })
    end
  end
  return entries, close
end

--- Is a value empty (written as `key:`)?
---@param v any
---@return boolean
local function empty(v)
  return v == nil or v == "" or (type(v) == "table" and #v == 0)
end

--- Set keys in a note's lines and return them (a new table). `changes` maps a key to its value,
--- or to `false` to remove the key. An existing key is rewritten where it is; a new one goes
--- before the first key ranked after it in `opts.order`, else at the end (new empty values are
--- skipped). Lines outside the frontmatter are left alone; a note without frontmatter gets one.
---@param lines string[]
---@param changes table<string, any>
---@param opts? { order?: string[] }
---@return string[]
function M.set(lines, changes, opts)
  opts = opts or {}
  local close = M.close(lines)
  if not close then
    local keys = vim.tbl_keys(changes)
    table.sort(keys)
    local fm = { "---" }
    for _, key in ipairs(keys) do
      if changes[key] ~= false and not empty(changes[key]) then
        table.insert(fm, M.line(key, changes[key]))
      end
    end
    if #fm == 1 then
      return vim.list_extend({}, lines)
    end
    table.insert(fm, "---")
    return vim.list_extend(fm, lines)
  end
  local out, done = { lines[1] }, {}
  local i = 2
  while i < close do
    local key = lines[i]:match("^([%w_%-]+):")
    local v = key and changes[key]
    if v == nil or done[key] then
      table.insert(out, lines[i])
    else
      done[key] = true
      if v ~= false then
        table.insert(out, M.line(key, v))
      end
      while i + 1 < close and lines[i + 1]:match("^%s+%-") do
        i = i + 1 -- the old value's block-list items go with it
      end
    end
    i = i + 1
  end
  -- new keys
  local rank = {}
  for i, k in ipairs(opts.order or {}) do
    rank[k] = i
  end
  local new = {}
  for key, v in pairs(changes) do
    if not done[key] and v ~= false and not empty(v) then
      table.insert(new, key)
    end
  end
  table.sort(new, function(a, b)
    local ra, rb = rank[a] or math.huge, rank[b] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return a < b
  end)
  for _, key in ipairs(new) do
    local at = #out + 1
    if rank[key] then
      for i = 2, #out do
        local k = out[i]:match("^([%w_%-]+):")
        if k and rank[k] and rank[k] > rank[key] then
          at = i
          break
        end
      end
    end
    table.insert(out, at, M.line(key, changes[key]))
  end
  for i = close, #lines do
    table.insert(out, lines[i])
  end
  return out
end

return M

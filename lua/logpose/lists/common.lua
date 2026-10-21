--- What the lists share: to-dos and linked tasks per note, people in short, project groupings.
local M = {}

--- Open to-dos, checked ones and linked tasks for every note.
---@param root string
---@param items logpose.Item[]
---@return table<string, { open: logpose.Item[], checked: integer, tasks: table[] }>
function M.note_info(root, items)
  local out = {}
  local function of(file)
    out[file] = out[file] or { open = {}, checked = 0, tasks = {} }
    return out[file]
  end
  for _, it in ipairs(items) do
    if it.kind == "todo" then
      local info = of(it.file)
      if it.checked then
        info.checked = info.checked + 1
      else
        table.insert(info.open, it)
      end
    end
  end
  local titles = {}
  for _, it in ipairs(items) do
    if it.kind == "task" then
      titles[it.file] = it
    end
  end
  for task, notes in pairs(require("logpose.links").related(root, items)) do
    for _, n in ipairs(notes) do
      local t = titles[task]
      table.insert(of(n.file).tasks, {
        file = task,
        title = t and t.title or vim.fn.fnamemodify(task, ":t:r"),
        status = t and t.status,
      })
    end
  end
  return out
end

--- Names, shortened to fit: "Ana, Bob +2".
---@param names string[]
---@param max? integer
---@return string
function M.people(names, max)
  max = max or 3
  local shown = {}
  for i = 1, math.min(#names, max) do
    local first = names[i]:match("^(%S+)") or names[i]
    if first:match("%.$") then -- "Dr. Ruiz", not "Dr."
      first = names[i]:match("^(%S+%s+%S+)") or first
    end
    table.insert(shown, first)
  end
  local out = table.concat(shown, ", ")
  if #names > max then
    out = out .. (" +%d"):format(#names - max)
  end
  return out
end

---@param v any
---@return string[]
function M.list(v)
  if type(v) == "table" then
    return vim.tbl_filter(function(x)
      return type(x) == "string" and x ~= ""
    end, v)
  elseif type(v) == "string" and v ~= "" then
    return vim.tbl_map(vim.trim, vim.split(v, ",", { trimempty = true }))
  end
  return {}
end

--- Projects to move to: the known ones, then none.
---@param s logpose.ListState
---@return { key: string, label: string }[]
function M.project_targets(s)
  local project = require("logpose.project")
  local out = {}
  for _, name in ipairs(project.known(s.root)) do
    table.insert(out, { key = name, label = project.title(s.root, name) })
  end
  table.insert(out, { key = "", label = "No project" })
  return out
end

--- The group of an entry's project.
---@param s logpose.ListState
---@param name? string
---@return { key: string, label: string }[]
function M.project_group(s, name)
  if not name or name == "" then
    return {}
  end
  return { { key = name, label = require("logpose.project").title(s.root, name) } }
end

--- Week groups: "Week of Mon 12 Oct · this week".
---@param iso? string
---@return { key: string, label: string }[]
function M.week_group(iso)
  if not iso then
    return {}
  end
  local date = require("logpose.util.date")
  local start = date.week_start_of(iso, require("logpose.config").get().period.week_start)
  local today = date.today()
  local this = date.week_start_of(today, require("logpose.config").get().period.week_start)
  local label = "Week of " .. date.short(start, today)
  if start == this then
    label = label .. " · this week"
  elseif start == date.add_days(this, -7) then
    label = label .. " · last week"
  elseif start == date.add_days(this, 7) then
    label = label .. " · next week"
  end
  return { { key = start, label = label } }
end

--- Month groups: "October 2026".
---@param iso? string
---@return { key: string, label: string }[]
function M.month_group(iso)
  if not iso or iso == "" then
    return {}
  end
  local y, m = iso:match("^(%d%d%d%d)%-(%d%d)")
  if not y then
    return {}
  end
  local names = {
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  }
  return { { key = y .. "-" .. m, label = names[tonumber(m)] .. " " .. y } }
end

--- A day in words: "Today", "Yesterday", "Tomorrow", else "Wed 14 Oct" (with the year when it
--- isn't this one).
---@param iso? string
---@return string
function M.day(iso)
  if not iso or iso == "" then
    return ""
  end
  local date = require("logpose.util.date")
  local today = date.today()
  if iso == today then
    return "Today"
  elseif iso == date.add_days(today, -1) then
    return "Yesterday"
  elseif iso == date.add_days(today, 1) then
    return "Tomorrow"
  end
  return date.short(iso, today)
end

--- The width of the date column for `entries` (by their `when`).
---@param entries table[]
---@return integer
function M.day_width(entries)
  local w = 0
  for _, e in ipairs(entries) do
    w = math.max(w, vim.fn.strdisplaywidth(M.day(e.when)))
  end
  return w
end

--- Newest first, then by title.
function M.newest(a, b)
  local da, db = a.when or "", b.when or ""
  if da ~= db then
    return da > db
  end
  return (a.item.title or ""):lower() < (b.item.title or ""):lower()
end

function M.oldest(a, b)
  local da, db = a.when or "", b.when or ""
  if da ~= db then
    return da < db
  end
  return (a.item.title or ""):lower() < (b.item.title or ""):lower()
end

function M.by_title(a, b)
  local ta, tb = (a.item.title or ""):lower(), (b.item.title or ""):lower()
  if ta ~= tb then
    return ta < tb
  end
  return a.key < b.key
end

--- The title column's width for `entries`.
---@param entries table[]
---@param width integer
---@param reserve integer room for the rest of the row
---@param max? integer
---@return integer
function M.title_width(entries, width, reserve, max)
  local longest = 0
  for _, e in ipairs(entries) do
    longest = math.max(longest, vim.fn.strdisplaywidth(e.item.title or e.item.text or ""))
  end
  return math.max(12, math.min(longest, max or 44, width - reserve))
end

--- Append `meta` chunks to a row, separated by dots.
---@param chunks table[]
---@param meta table[]
---@return table[]
function M.with_meta(chunks, meta)
  for i, m in ipairs(meta) do
    table.insert(chunks, { i == 1 and "  " or "  ·  ", "LogposeListMeta" })
    table.insert(chunks, m)
  end
  return chunks
end

--- Swap `from` for `to` in a frontmatter list (tags, projects) of `file`.
---@param root string
---@param file string
---@param kind string
---@param key string
---@param current string[]
---@param from string
---@param to string
---@return string path
function M.swap_in_list(root, file, kind, key, current, from, to)
  local list = {}
  for _, v in ipairs(current) do
    if v:lower() ~= from:lower() and v:lower() ~= to:lower() then
      table.insert(list, v)
    end
  end
  if to ~= "" then
    table.insert(list, to)
  end
  local path = require("logpose.edit.save").note(root, file, kind, { [key] = list })
  return path
end

return M

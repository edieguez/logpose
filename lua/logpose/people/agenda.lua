--- What to bring up at the next 1:1: the lines under `## Next 1:1` on a person's page. Starting a
--- 1:1 with them moves those lines into the new meeting note (under `## Topics`, or a new
--- `## Agenda`), so each lives in one place; `n` on the people list adds one.
local fs = require("logpose.util.fs")

local M = {}

M.HEADING = "Next 1:1"

--- The heading's line and the rows of its non-blank lines.
---@param lines string[]
---@return integer? heading, integer[] rows
function M.find(lines)
  local heading
  local rows = {}
  for i, l in ipairs(lines) do
    local h = l:match("^##%s+(.-)%s*$")
    if h or l:match("^#%s") then
      if heading then
        break
      end
      if h and h:lower() == M.HEADING:lower() then
        heading = i
      end
    elseif heading and vim.trim(l) ~= "" then
      table.insert(rows, i)
    end
  end
  return heading, rows
end

--- The items waiting for the next 1:1 on a page.
---@param page string
---@return string[]
function M.items(page)
  local lines = fs.current_lines(page) or {}
  local _, rows = M.find(lines)
  return vim.tbl_map(function(r)
    return lines[r]
  end, rows)
end

--- Add an item for the next 1:1 (a `## Next 1:1` section is added when the page has none).
---@param page string
---@param text string
function M.add(page, text)
  local item = text:match("^%s*[-*+]%s") and text or ("- " .. vim.trim(text))
  local ok, err = fs.update_lines(page, function(lines)
    local heading, rows = M.find(lines)
    if not heading then
      while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines)
      end
      vim.list_extend(lines, { "", "## " .. M.HEADING, "", item })
      return lines
    end
    table.insert(lines, (rows[#rows] or (heading + 1)) + 1, item)
    return lines
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
end

--- Remove the items from the page (they went to a meeting), leaving the heading.
---@param page string
---@param taken string[] the lines that went (removed only if still there)
function M.clear(page, taken)
  local want = {}
  for _, l in ipairs(taken) do
    want[l] = (want[l] or 0) + 1
  end
  local ok, err = fs.update_lines(page, function(lines)
    local _, rows = M.find(lines)
    local changed = false
    for k = #rows, 1, -1 do
      local l = lines[rows[k]]
      if want[l] and want[l] > 0 then
        want[l] = want[l] - 1
        table.remove(lines, rows[k])
        changed = true
      end
    end
    return changed and lines or nil
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
end

M.UPDATES = "Updates"

--- The day of the last 1:1 with `p` before `iso` (any meeting with them as `with:`), or nil.
---@param items logpose.Item[]
---@param p logpose.Person
---@param iso string
---@param path string the new note (left out)
---@return string?
function M.last_one_on_one(items, p, iso, path)
  local slugify = require("logpose.util.text").slugify
  local last
  for _, it in ipairs(items) do
    local with = it.kind == "note" and it.file_type == "meeting" and (it.fields or {}).with
    if type(with) == "string" and p.slugs[slugify(with)] and it.date and it.file ~= path and it.date <= iso then
      if not last or it.date > last then
        last = it.date
      end
    end
  end
  return last
end

--- What to catch up on with `p` in a new 1:1: the open tasks they're assigned (with their column),
--- and the tasks they're a stakeholder in that moved since the last 1:1 with them (none before the
--- first). Lines `- <link> — what`, links written from `path`; empty when there's nothing.
---@param root string
---@param p logpose.Person
---@param iso string the meeting's day
---@param path string the new meeting note
---@return string[]
function M.updates(root, p, iso, path)
  local items = require("logpose.index").build(root)
  local taskfile = require("logpose.taskfile")
  local link = require("logpose.link")
  local slugify = require("logpose.util.text").slugify
  local since = M.last_one_on_one(items, p, iso, path)
  local function is_them(name)
    return type(name) == "string" and p.slugs[slugify((name:gsub("^@", "")))] == true
  end
  local assigned, moved = {}, {}
  for _, it in ipairs(items) do
    if it.kind == "task" and not it.archived then
      local title = it.title or it.text
      local function line(what)
        return { title = title, line = ("- %s — %s"):format(link.make(path, it.file, title, root), what) }
      end
      if is_them(it.assignee) and not taskfile.is_closed(it.status) then
        local what = taskfile.label(it.status or "")
        if it.blocked then
          what = what .. ", blocked" .. (it.blocked ~= "yes" and (": " .. it.blocked) or "")
        end
        table.insert(assigned, line(what))
      elseif since and vim.tbl_contains(vim.tbl_map(is_them, it.stakeholders or {}), true) then
        local m = require("logpose.notes.status").moves(fs.read_lines(it.file) or {}, since, iso)
        if #m > 0 and m[1].from ~= m[#m].to then
          local first, last = m[1], m[#m]
          table.insert(moved, line(first.from and (first.from .. " → " .. last.to) or ("new · " .. last.to)))
        end
      end
    end
  end
  local out = {}
  for _, list in ipairs({ assigned, moved }) do
    table.sort(list, function(a, b)
      return a.title:lower() < b.title:lower()
    end)
    for _, x in ipairs(list) do
      table.insert(out, x.line)
    end
  end
  return out
end

--- Put `## Updates` with `lines` in a meeting note's body, after the title (before its topics).
--- Returns how many lines went in before `row`.
---@param body string[]
---@param lines string[]
---@param row integer the cursor's row in the body
---@return integer shift
function M.insert_updates(body, lines, row)
  local at = 0
  for i, l in ipairs(body) do
    if l:match("^#%s") then
      at = i
      break
    end
  end
  local block = vim.list_extend({ "", "## " .. M.UPDATES, "" }, lines)
  table.insert(block, "")
  for k, l in ipairs(block) do
    table.insert(body, at + k, l)
  end
  return row > at and #block or 0
end

--- Put `items` in a meeting note's body: under `## Topics` (or `## Agenda`) when it has one,
--- else in a new `## Agenda` after the title. Returns how many lines went in before `row`.
---@param body string[]
---@param items string[]
---@param row integer the cursor's row in the body
---@return integer shift
function M.insert(body, items, row)
  local at
  for i, l in ipairs(body) do
    local h = l:match("^##%s+(.-)%s*$")
    if h and (h:lower() == "topics" or h:lower() == "agenda") then
      at = i
      break
    end
  end
  local block
  if at then
    block = vim.list_extend({ "" }, items)
  else
    at = 0
    for i, l in ipairs(body) do
      if l:match("^#%s") then
        at = i
        break
      end
    end
    block = vim.list_extend({ "", "## Agenda", "" }, items)
  end
  for k, l in ipairs(block) do
    table.insert(body, at + k, l)
  end
  return row > at and #block or 0
end

return M

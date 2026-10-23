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

--- Markdown helpers: dated `## YYYY-MM-DD` headings, blank-line trimming and tidying (markdownlint
--- hygiene), and wrapping.
local date = require("logpose.util.date")

local M = {}

---@param line string
---@return string? iso date if the line is a `## YYYY-MM-DD` heading
function M.heading_date(line)
  local iso = line:match("^##%s+(%d%d%d%d%-%d%d%-%d%d)%s*$")
  if iso and date.is_iso(iso) then
    return iso
  end
  return nil
end

--- Lines with leading and/or trailing blank lines removed.
---@param lines string[]
---@param leading? boolean
---@param trailing? boolean
---@return string[]
function M.trim_blank(lines, leading, trailing)
  local first, last = 1, #lines
  if leading ~= false then
    while first <= last and vim.trim(lines[first]) == "" do
      first = first + 1
    end
  end
  if trailing ~= false then
    while last >= first and vim.trim(lines[last]) == "" do
      last = last - 1
    end
  end
  return vim.list_slice(lines, first, last)
end

--- Blank-line hygiene for markdownlint (MD009, MD012, MD022, MD031, MD032, MD047, MD058):
--- one blank line around headings, lists, tables and code fences, no runs of blank lines,
--- no blank lines at the end, no stray trailing spaces (two, a hard break, are kept).
--- Frontmatter and the inside of code fences are left alone. Text is never reflowed.
---@param lines string[]
---@param row? integer a line (1-based) to follow, e.g. the cursor
---@return string[] lines, integer? row  where `row` ended up
function M.tidy(lines, row)
  local out = {}
  local new_row
  local i = 1
  if lines[1] == "---" then
    for j = 2, #lines do
      if lines[j] == "---" then
        for k = 1, j do
          table.insert(out, lines[k])
        end
        if row and row <= j then
          new_row = row
        end
        i = j + 1
        break
      end
    end
  end
  local body_start = #out + 1
  local function blank_last()
    return #out < body_start or out[#out] == ""
  end
  local function need_blank()
    if not blank_last() then
      table.insert(out, "")
    end
  end
  local fence, in_list, in_table = nil, false, false
  local after_block = false -- a heading, fence or table just ended: next content needs a blank
  while i <= #lines do
    local line = lines[i]
    if fence then
      table.insert(out, line)
      if line:match("^%s*" .. fence .. "%s*$") then
        fence = nil
        after_block = true
      end
    else
      local trimmed = line:gsub("%s+$", "")
      if line:match("%S  $") and not line:match("%S   +$") then
        trimmed = trimmed .. "  " -- a hard line break
      end
      local is_blank = trimmed == ""
      local open = trimmed:match("^%s*(```+)") or trimmed:match("^%s*(~~~+)")
      local is_heading = trimmed:match("^#+%s") ~= nil or trimmed:match("^#+$") ~= nil
      local is_item = trimmed:match("^%s*[-*+]%s") ~= nil
        or trimmed:match("^%s*[-*+]$") ~= nil
        or trimmed:match("^%s*%d+[.)]%s") ~= nil
      local is_row = trimmed:match("^%s*|") ~= nil
      if is_blank then
        need_blank()
        in_list, in_table, after_block = false, false, false
      elseif open then
        need_blank()
        table.insert(out, trimmed)
        fence = open:sub(1, 3)
        in_list, in_table, after_block = false, false, false
      elseif is_heading then
        need_blank()
        table.insert(out, trimmed)
        in_list, in_table, after_block = false, false, true
      elseif is_row then
        if not in_table then
          need_blank()
        end
        table.insert(out, trimmed)
        in_table, in_list, after_block = true, false, false
      else
        if after_block or in_table or (is_item and not in_list) then
          need_blank()
        end
        table.insert(out, trimmed)
        after_block, in_table = false, false
        if is_item then
          in_list = true
        end
        -- other lines keep `in_list` (continuation lines belong to the list)
      end
    end
    if i == row then
      new_row = math.max(#out, 1)
    end
    i = i + 1
  end
  while #out >= body_start and out[#out] == "" do
    table.remove(out)
  end
  -- An empty body after frontmatter keeps one blank line, for the cursor.
  if #out < body_start and body_start > 1 and i > body_start then
    table.insert(out, "")
    if row then
      new_row = #out
    end
    return out, new_row
  end
  -- No blank line right after the frontmatter either.
  while out[body_start] == "" do
    table.remove(out, body_start)
    if new_row and new_row > body_start then
      new_row = new_row - 1
    end
  end
  if new_row then
    new_row = math.max(1, math.min(new_row, #out))
  end
  return out, new_row
end

--- `M.tidy` for a whole text and a {row, col} cursor in it. Returns text ending in a newline.
---@param text string
---@param cursor? integer[]
---@return string text, integer[]? cursor
function M.tidy_text(text, cursor)
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  local out, row = M.tidy(lines, cursor and cursor[1])
  local new_cursor = cursor and { row or cursor[1], row == cursor[1] and cursor[2] or 0 } or nil
  return table.concat(out, "\n") .. "\n", new_cursor
end

--- Wrap a list item to `width` columns (MD013) at spaces outside links and code spans;
--- continuation lines are indented to the item's text. Other lines are returned as they are.
---@param line string
---@param width integer
---@return string[]
function M.wrap(line, width)
  local marker = line:match("^(%s*[-*+]%s+%[.%]%s+)") or line:match("^(%s*[-*+]%s+)") or line:match("^(%s*%d+[.)]%s+)")
  if not marker or vim.fn.strdisplaywidth(line) <= width then
    return { line }
  end
  local indent = string.rep(" ", #(line:match("^(%s*[-*+%d.)]+%s+)") or marker))
  -- Words, keeping [[wiki links]], [text](links) and `code` (with what's glued to them) whole.
  local words, rest = {}, line:sub(#marker + 1)
  local i, cur = 1, ""
  while i <= #rest do
    local c = rest:sub(i, i)
    local chunk
    if rest:sub(i, i + 1) == "[[" then
      local e = rest:find("]]", i + 2, true)
      chunk = rest:sub(i, e and e + 1 or #rest)
    elseif c == "[" then
      local e = rest:find("%]%b()", i)
      local close = e and rest:find(")", e, true)
      if e and close then
        local _, stop = rest:find("%b()", e + 1)
        chunk = rest:sub(i, stop)
      else
        chunk = c
      end
    elseif c == "`" then
      local e = rest:find("`", i + 1, true)
      chunk = rest:sub(i, e or #rest)
    else
      chunk = c
    end
    if chunk == " " then
      if cur ~= "" then
        table.insert(words, cur)
      end
      cur = ""
    else
      cur = cur .. chunk
    end
    i = i + #chunk
  end
  if cur ~= "" then
    table.insert(words, cur)
  end
  local out, buf = {}, marker
  local first = true
  for _, w in ipairs(words) do
    local candidate = (buf == marker or buf == indent) and (buf .. w) or (buf .. " " .. w)
    if vim.fn.strdisplaywidth(candidate) > width and buf ~= marker and buf ~= indent then
      table.insert(out, buf)
      buf = indent .. w
      first = false
    else
      buf = candidate
    end
  end
  table.insert(out, buf)
  return out
end

return M

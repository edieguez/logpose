--- Markdown section helpers for files made of `## YYYY-MM-DD` sections (INBOX, DONE, archives).
---
--- A document is a list of blocks:
---   { kind = "preamble", lines }                 -- everything before the first `## ` heading
---   { kind = "date", date, lines }              -- `## YYYY-MM-DD` heading + body
---   { kind = "other", lines }                   -- any other `## ` heading + body
--- `lines[1]` of a heading block is the heading itself. Rendering untouched blocks is lossless.
local date = require("logpose.util.date")

local M = {}

---@class logpose.Block
---@field kind "preamble"|"date"|"other"
---@field date? string
---@field lines string[]

---@class logpose.Doc
---@field blocks logpose.Block[]
---@field final_newline boolean

---@param line string
---@return string? iso date if the line is a `## YYYY-MM-DD` heading
function M.heading_date(line)
  local iso = line:match("^##%s+(%d%d%d%d%-%d%d%-%d%d)%s*$")
  if iso and date.is_iso(iso) then
    return iso
  end
  return nil
end

---@param content string
---@return logpose.Doc
function M.parse(content)
  local lines = vim.split(content, "\n", { plain = true })
  local final_newline = false
  if lines[#lines] == "" then
    table.remove(lines)
    final_newline = #lines > 0 or content == "\n"
  end
  local blocks = { { kind = "preamble", lines = {} } }
  for _, line in ipairs(lines) do
    if line:match("^##%s") then
      local iso = M.heading_date(line)
      table.insert(blocks, { kind = iso and "date" or "other", date = iso, lines = { line } })
    else
      table.insert(blocks[#blocks].lines, line)
    end
  end
  return { blocks = blocks, final_newline = final_newline }
end

---@param doc logpose.Doc
---@return string
function M.render(doc)
  local lines = {}
  for _, block in ipairs(doc.blocks) do
    vim.list_extend(lines, block.lines)
  end
  local s = table.concat(lines, "\n")
  if doc.final_newline and #lines > 0 then
    s = s .. "\n"
  end
  return s
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

--- Body of a heading block (without the heading).
---@param block logpose.Block
---@return string[]
function M.body(block)
  return vim.list_slice(block.lines, 2)
end

--- Date order of a document's sections: "newest_first", "oldest_first" or nil if unknown.
---@param doc logpose.Doc
---@return "newest_first"|"oldest_first"|nil
function M.detect_order(doc)
  local prev
  for _, block in ipairs(doc.blocks) do
    if block.kind == "date" then
      if prev and prev ~= block.date then
        return block.date < prev and "newest_first" or "oldest_first"
      end
      prev = block.date
    end
  end
  return nil
end

return M

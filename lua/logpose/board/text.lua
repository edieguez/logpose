--- Board text helpers: fit and wrap text (and highlighted chunks) to a width in display cells.
local config = require("logpose.config")

local M = {}

--- Text cut or padded to exactly `w` display cells.
---@param s string
---@param w integer
---@return string
function M.fit(s, w)
  if w <= 0 then
    return ""
  end
  local width = vim.fn.strdisplaywidth(s)
  if width <= w then
    return s .. string.rep(" ", w - width)
  end
  local out, used = {}, 0
  local n = vim.fn.strchars(s)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local cw = vim.fn.strdisplaywidth(ch)
    if used + cw > w - 1 then
      break
    end
    table.insert(out, ch)
    used = used + cw
  end
  -- "…" marks the cut; ASCII icons use "~" so the board stays plain ASCII.
  local ellipsis = config.get().board.icons == "ascii" and "~" or "…"
  return table.concat(out) .. ellipsis .. string.rep(" ", w - used - 1)
end

--- Word-wrap `s` into at most `max` lines of `w` cells (the last one cut with …).
---@param s string
---@param w integer
---@param max integer
---@return string[]
function M.wrap(s, w, max)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    local candidate = cur == "" and word or (cur .. " " .. word)
    if vim.fn.strdisplaywidth(candidate) <= w or cur == "" then
      cur = candidate
    else
      table.insert(lines, cur)
      cur = word
    end
  end
  if cur ~= "" then
    table.insert(lines, cur)
  end
  if #lines > max then
    local rest = table.concat(vim.list_slice(lines, max), " ")
    lines = vim.list_slice(lines, 1, max - 1)
    table.insert(lines, rest)
  end
  for i, l in ipairs(lines) do
    if vim.fn.strdisplaywidth(l) > w then
      lines[i] = vim.trim(M.fit(l, w))
    end
  end
  return #lines > 0 and lines or { "" }
end

---@alias logpose.Chunk { [1]: string, [2]: string? }  text, highlight group

--- Chunks cut or padded to exactly `w` display cells.
---@param chunks logpose.Chunk[]
---@param w integer
---@return logpose.Chunk[]
function M.fit_chunks(chunks, w)
  local out, used = {}, 0
  for _, c in ipairs(chunks) do
    local cw = vim.fn.strdisplaywidth(c[1])
    if used + cw <= w then
      table.insert(out, c)
      used = used + cw
    else
      local room = w - used
      if room > 0 then
        table.insert(out, { vim.trim(M.fit(c[1], room)), c[2] })
        used = used + vim.fn.strdisplaywidth(out[#out][1])
      end
      break
    end
  end
  if used < w then
    table.insert(out, { string.rep(" ", w - used) })
  end
  return out
end

return M

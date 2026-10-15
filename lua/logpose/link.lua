--- Link generation (wiki or markdown style).
local config = require("logpose.config")

local M = {}

---@param path string
---@return string[]
local function parts(path)
  return vim.split(vim.fs.normalize(path), "/", { trimempty = true })
end

--- Relative path from directory `from_dir` to `to` (both absolute).
---@param from_dir string
---@param to string
---@return string
function M.relpath(from_dir, to)
  local a, b = parts(from_dir), parts(to)
  local i = 1
  while i <= #a and i <= #b and a[i] == b[i] do
    i = i + 1
  end
  local out = {}
  for _ = i, #a do
    table.insert(out, "..")
  end
  for j = i, #b do
    table.insert(out, b[j])
  end
  return #out > 0 and table.concat(out, "/") or "."
end

--- The link target written into `source` for `target`: a wiki path (relative to `link_base`,
--- no .md) or a markdown relative path.
---@param source string
---@param target string
---@param root string
---@param style? "wiki"|"markdown"
---@return string
function M.target(source, target, root, style)
  style = style or config.get().link_style
  if style == "markdown" then
    return M.relpath(vim.fs.dirname(source), target)
  end
  local base = vim.fs.joinpath(root, config.get().link_base)
  return (M.relpath(base, target):gsub("%.md$", ""))
end

--- Link to `target` from the note at `source` (absolute paths).
---@param source string file the link is written into
---@param target string file being linked
---@param label string
---@param root string journal root
---@param style? "wiki"|"markdown"
---@return string
function M.make(source, target, label, root, style)
  style = style or config.get().link_style
  local rel = M.target(source, target, root, style)
  if style == "markdown" then
    if rel:find("[%s()<>]") then
      rel = "<" .. rel .. ">"
    end
    return ("[%s](%s)"):format(label, rel)
  end
  if label == "" or label == rel then
    return ("[[%s]]"):format(rel)
  end
  return ("[[%s|%s]]"):format(rel, label)
end

return M

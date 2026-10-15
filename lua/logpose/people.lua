--- People: names from attendees, 1:1s (`with:`) and @mentions, read from the index.
local config = require("logpose.config")

local M = {}

--- Known people, most involved first.
---@param root? string
---@return { slug: string, name: string, count: integer }[]
function M.known(root)
  root = root or config.resolve_root()
  if not root then
    return {}
  end
  return require("logpose.index").people(require("logpose.index").build(root))
end

--- Completion for a name, or the last name in a comma-separated list.
---@param arglead string
---@return string[]
function M.complete(arglead)
  local base, partial = arglead:match("^(.*,%s*)(.-)$")
  if not base then
    base, partial = "", arglead
  end
  local out = {}
  for _, p in ipairs(M.known()) do
    if vim.startswith(p.name:lower(), partial:lower()) then
      table.insert(out, base .. p.name)
    end
  end
  return out
end

_G.LogposeCompletePeople = function(arglead)
  return M.complete(arglead)
end

return M

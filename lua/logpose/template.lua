--- Templates: lookup (journal overrides -> shipped defaults) and rendering.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")

local M = {}

local CURSOR = "{cursor}"

--- Directory holding the templates shipped with the plugin.
---@return string
function M.builtin_dir()
  local this = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(this))), "templates")
end

--- Find a template by name: `<root>/<dirs.templates>/<name>.md`, then the shipped one.
---@param name string
---@param root string
---@return string content, string path
function M.load(name, root)
  local candidates = {
    fs.join(config.path("templates", root), name .. ".md"),
    fs.join(M.builtin_dir(), name .. ".md"),
  }
  for _, path in ipairs(candidates) do
    local content = fs.read_file(path)
    if content then
      return content, path
    end
  end
  error(("logpose: template %q not found (looked in %s)"):format(name, table.concat(candidates, ", ")), 0)
end

--- Standard variables for a date.
---@param iso string
---@param extra? table<string, string>
---@return table<string, string>
function M.vars(iso, extra)
  local vars = {
    date = iso,
    time = date.now_hhmm():gsub("^(%d%d)(%d%d)$", "%1:%2"),
    weekday = date.weekday_name(iso),
    iso_week = date.iso_week(iso),
    sprint = "",
  }
  return vim.tbl_extend("force", vars, extra or {})
end

--- Substitute `{name}` variables. Unknown variables are left as they are.
--- Uses a function replacement, so `%` in values is safe.
---@param s string
---@param vars table<string, string>
---@return string
function M.substitute(s, vars)
  return (
    s:gsub("{([%w_]+)}", function(key)
      local v = vars[key]
      if v == nil then
        return nil -- keep the original text
      end
      return tostring(v)
    end)
  )
end

---@class logpose.Rendered
---@field text string
---@field cursor integer[]  {line (1-based), col (0-based bytes)} within `text`

--- Render a template. `{cursor}` marks where the cursor goes and is removed;
--- without it the cursor goes to the last non-empty line.
---@param tpl string
---@param vars table<string, string>
---@return logpose.Rendered
function M.render(tpl, vars)
  local s, e = tpl:find(CURSOR, 1, true)
  local before, after
  if s then
    before = tpl:sub(1, s - 1)
    after = tpl:sub(e + 1):gsub(vim.pesc(CURSOR), "")
  else
    before, after = tpl, ""
  end
  before = M.substitute(before, vars)
  after = M.substitute(after, vars)
  local text = before .. after

  local cursor
  if s then
    local lines = vim.split(before, "\n", { plain = true })
    cursor = { #lines, #lines[#lines] }
  else
    local lines = vim.split(text, "\n", { plain = true })
    local last = #lines
    while last > 1 and lines[last] == "" do
      last = last - 1
    end
    cursor = { last, 0 }
  end
  return { text = text, cursor = cursor }
end

return M

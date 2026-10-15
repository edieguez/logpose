--- Daily notes: `:Logpose daily [today|prev|next|YYYY-MM-DD]`.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local template = require("logpose.template")
local ui = require("logpose.util.ui")

local M = {}

---@param iso string
---@param root string
---@return string
function M.path(iso, root)
  return fs.join(config.path("daily", root), config.get().affixes.daily .. iso .. ".md")
end

--- Date of a daily-note path, or nil if `path` isn't one.
---@param path string
---@return string?
function M.date_of(path)
  local name = vim.fs.basename(path)
  local iso = name:match("^" .. vim.pesc(config.get().affixes.daily) .. "(%d%d%d%d%-%d%d%-%d%d)%.md$")
  if iso and date.is_iso(iso) then
    return iso
  end
  return nil
end

--- Turn a command argument into a date. `prev`/`next` step by workdays from the
--- current buffer's daily note (or today).
---@param arg? string
---@return string
function M.resolve_date(arg)
  if arg == nil or arg == "" or arg == "today" then
    return date.today()
  end
  if arg == "prev" or arg == "next" then
    local base = M.date_of(vim.api.nvim_buf_get_name(0)) or date.today()
    local workdays = config.get().workdays
    return arg == "prev" and date.prev_workday(base, workdays) or date.next_workday(base, workdays)
  end
  if date.is_iso(arg) then
    return arg
  end
  error(("logpose: invalid date %q (use today, prev, next or YYYY-MM-DD)"):format(arg), 0)
end

--- Create the daily note for `iso` if it doesn't exist. Does not open it.
---@param iso string
---@param root string
---@return string path, boolean created, integer[]? cursor
function M.ensure(iso, root)
  local path = M.path(iso, root)
  if fs.exists(path) then
    return path, false
  end
  local rendered = template.render(template.load("daily", root), template.vars(iso))
  local ok, err = fs.write_file(path, rendered.text)
  if not ok then
    error(err, 0)
  end
  return path, true, rendered.cursor
end

--- Create (if needed) and open the daily note for `iso`.
---@param iso string
---@param root string
function M.open_date(iso, root)
  local path, created, cursor = M.ensure(iso, root)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if created and cursor then
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
end

--- Create (if needed) and open the daily note. Offers onboarding when there's no journal yet.
---@param arg? string today|prev|next|YYYY-MM-DD
function M.open(arg)
  local iso = M.resolve_date(arg) -- resolve now: `prev`/`next` depend on the current buffer
  config.with_root(ui.safely(function(root)
    M.open_date(iso, root)
  end))
end

---@param opts logpose.CommandOpts
function M.command(opts)
  if #opts.args > 1 then
    error("logpose: usage :Logpose daily [today|prev|next|YYYY-MM-DD]", 0)
  end
  M.open(opts.args[1])
end

---@return string[]
function M.complete(_, args)
  if #args == 0 then
    return { "today", "prev", "next" }
  end
  return {}
end

return M

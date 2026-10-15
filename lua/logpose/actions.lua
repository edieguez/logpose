--- `:Logpose actions [open|mine|overdue|all] [filters…]`: action items from meeting notes
--- (and daily notes if `actions.include_daily`), with `@owner` and `due:YYYY-MM-DD`.
local config = require("logpose.config")
local date = require("logpose.util.date")
local index = require("logpose.index")
local query = require("logpose.query")
local ui = require("logpose.util.ui")

local M = {}

M.MODES = { "open", "mine", "overdue", "all" }

--- Owners (`@name`, lowercased, without `@`) and due date in a task's text.
---@param text string
---@return string[] owners, string? due
function M.meta(text)
  local owners = {}
  for name in (" " .. text):gmatch("%s@([%w_][%w_%.%-]*)") do
    table.insert(owners, (name:gsub("[%.%-]+$", "")):lower())
  end
  local due = text:match("due:(%d%d%d%d%-%d%d%-%d%d)")
  if due and not date.is_iso(due) then
    due = nil
  end
  return owners, due
end

---@param me? string
---@return string?
local function normalize_me(me)
  if not me or me == "" then
    return nil
  end
  return (me:gsub("^@", "")):lower()
end

---@class logpose.Action: logpose.Item
---@field owners string[]
---@field due? string
---@field overdue boolean

--- Action items for `mode`, filtered by `args` (same filters as :Logpose find).
---@param root string
---@param mode string
---@param args string[]
---@param today string
---@return logpose.Action[]
function M.collect(root, mode, args, today)
  local opts = config.get()
  local q = query.parse(args)
  local me = normalize_me(opts.me)
  local out = {}
  for _, it in ipairs(index.build(root)) do
    local from_note = it.note_type == "meeting" or (opts.actions.include_daily and it.note_type == "daily")
    if it.kind == "task" and from_note and query.match(it, q) then
      local owners, due = M.meta(it.text)
      it.owners, it.due = owners, due
      it.overdue = not it.checked and due ~= nil and due < today
      local keep
      if mode == "all" then
        keep = true
      elseif mode == "open" then
        keep = not it.checked
      elseif mode == "overdue" then
        keep = it.overdue
      elseif mode == "mine" then
        local mine = #owners == 0 and opts.actions.unassigned_mine
        if me and vim.tbl_contains(owners, me) then
          mine = true
        end
        keep = not it.checked and mine
      end
      if keep then
        table.insert(out, it)
      end
    end
  end
  -- Due date first (soonest), then oldest meeting first: the longest-waiting items surface.
  table.sort(out, function(a, b)
    if a.checked ~= b.checked then
      return not a.checked
    end
    if (a.due or "~") ~= (b.due or "~") then
      return (a.due or "~") < (b.due or "~")
    end
    if (a.date or "") ~= (b.date or "") then
      return (a.date or "") < (b.date or "")
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.lnum < b.lnum
  end)
  return out
end

---@param it logpose.Action
---@return string
function M.display(it)
  local where = it.title or vim.fn.fnamemodify(it.file, ":t:r")
  local project = it.project and ("  @" .. it.project) or ""
  local flag = it.overdue and "  (overdue)" or ""
  return ("[%s] %s%s  · %s%s"):format(it.checked and "x" or " ", it.text, flag, where, project)
end

---@param root string
---@param mode string
---@param args string[]
function M.show(root, mode, args)
  local items = M.collect(root, mode, args, date.today())
  local title = ("logpose actions: %s%s"):format(mode, #args > 0 and (" " .. table.concat(args, " ")) or "")
  if #items == 0 then
    local what = mode == "all" and "" or (mode .. " ")
    vim.notify(("logpose: no %saction items"):format(what), vim.log.levels.INFO)
    return
  end
  if config.get().actions.output == "picker" then
    local picker = require("logpose.picker")
    picker.pick(
      vim.tbl_map(function(it)
        return { display = M.display(it), file = it.file, lnum = it.lnum }
      end, items),
      { prompt = "Actions: " .. mode, cwd = root }
    )
    return
  end
  vim.fn.setqflist({}, " ", {
    title = title,
    items = vim.tbl_map(function(it)
      return { filename = it.file, lnum = it.lnum, col = 1, text = M.display(it) }
    end, items),
  })
  vim.cmd("copen")
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local args = vim.list_extend({}, opts.args)
  local mode = "open"
  if args[1] and vim.tbl_contains(M.MODES, args[1]) then
    mode = table.remove(args, 1)
  end
  query.parse(args) -- validate before any prompt
  config.with_root(ui.safely(function(root)
    M.show(root, mode, args)
  end))
end

---@return string[]
function M.complete(arglead, args)
  if #args == 0 then
    return vim.list_extend(vim.deepcopy(M.MODES), require("logpose.search").complete(arglead, { "tasks" }))
  end
  return require("logpose.search").complete(arglead, args)
end

return M

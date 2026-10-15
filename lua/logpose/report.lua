--- `:Logpose report[!] [week|sprint] [offset] [filters…]`: a summary of one week or sprint,
--- with a review section. `!` also saves it to `dirs.reports`.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local index = require("logpose.index")
local link = require("logpose.link")
local query = require("logpose.query")
local ui = require("logpose.util.ui")

local M = {}

---@param items logpose.Item[]
---@param p logpose.Period
---@return logpose.Item[]
local function in_period(items, p)
  return vim.tbl_filter(function(it)
    return it.date ~= nil and it.date >= p.start and it.date <= p.finish
  end, items)
end

---@param list table
---@param key fun(x): string
---@return string[] keys, table<string, table> groups
local function group_by(list, key)
  local groups, keys = {}, {}
  for _, x in ipairs(list) do
    local k = key(x)
    if not groups[k] then
      groups[k] = {}
      table.insert(keys, k)
    end
    table.insert(groups[k], x)
  end
  table.sort(keys)
  return keys, groups
end

---@param out string[]
---@param heading string
---@param n integer
local function section(out, heading, n)
  table.insert(out, "")
  table.insert(out, ("## %s (%d)"):format(heading, n))
end

--- Build the report lines.
---@param root string
---@param p logpose.Period
---@param args string[] filters (project:, #tag, person:…)
---@param today string
---@param dest string file the links are written from
---@return string[]
function M.build(root, p, args, today, dest)
  local q = query.parse(args, today)
  local all = index.build(root)
  local items = query.filter(all, q)
  local function ref(it)
    return link.make(dest, it.file, it.title or vim.fn.fnamemodify(it.file, ":t:r"), root)
  end
  local done_path = config.path("done", root)
  local done_dir = config.path("done_entries", root)

  local title = "# Report: " .. p.label
  if #args > 0 then
    title = title .. " — " .. table.concat(args, " ")
  end
  local out = { title, "", ("Generated %s."):format(today) }

  -- Done: DONE.md and the done archives.
  local done = vim.tbl_filter(function(it)
    return it.kind == "task" and it.checked and (it.file == done_path or vim.startswith(it.file, done_dir .. "/"))
  end, in_period(items, p))
  section(out, "Done", #done)
  local dates, by_date = group_by(done, function(it)
    return it.date
  end)
  for _, d in ipairs(dates) do
    table.insert(out, "### " .. d)
    for _, it in ipairs(by_date[d]) do
      table.insert(out, "- " .. it.text)
    end
  end

  -- Meetings held, by type.
  local meetings = vim.tbl_filter(function(it)
    return it.kind == "note" and it.note_type == "meeting"
  end, in_period(items, p))
  section(out, "Meetings", #meetings)
  local types, by_type = group_by(meetings, function(it)
    return it.type or "other"
  end)
  for _, t in ipairs(types) do
    table.insert(out, "### " .. t)
    table.sort(by_type[t], function(a, b)
      return a.date < b.date
    end)
    for _, it in ipairs(by_type[t]) do
      table.insert(out, ("- %s %s%s"):format(it.date, ref(it), it.project and ("  @" .. it.project) or ""))
    end
  end

  -- Decisions.
  local decisions = vim.tbl_filter(function(it)
    return it.kind ~= "note" and it.section ~= nil and it.section:find("decision", 1, true) ~= nil
  end, in_period(items, p))
  section(out, "Decisions", #decisions)
  for _, it in ipairs(decisions) do
    table.insert(out, ("- %s (%s)"):format(it.text, ref(it)))
  end

  -- Open action items from meetings in the period.
  local actions = require("logpose.actions")
  local open = in_period(actions.collect(root, "open", args, today), p)
  section(out, "Open action items", #open)
  for _, it in ipairs(open) do
    table.insert(out, ("- [ ] %s (%s)"):format(it.text, ref(it)))
  end

  -- Review: what needs attention now (not limited to the period).
  table.insert(out, "")
  table.insert(out, "## Review")
  local overdue = actions.collect(root, "overdue", args, today)
  table.insert(out, "")
  table.insert(out, ("### Overdue actions (%d)"):format(#overdue))
  local keys, by_key = group_by(overdue, function(it)
    return it.project or "no project"
  end)
  for _, k in ipairs(keys) do
    for _, it in ipairs(by_key[k]) do
      local owners = #it.owners > 0 and (" @" .. table.concat(it.owners, " @")) or ""
      table.insert(out, ("- [%s] %s (due %s%s)"):format(k, it.text, it.due, owners))
    end
  end

  local stale_before = date.add_days(today, -config.get().review.stale_days)
  local stale = vim.tbl_filter(function(it)
    return it.kind == "task" and not it.checked and it.date ~= nil and it.date < stale_before
  end, items)
  table.insert(out, "")
  table.insert(out, ("### Stale open tasks, older than %d days (%d)"):format(config.get().review.stale_days, #stale))
  for _, it in ipairs(stale) do
    table.insert(out, ("- %s %s (%s)"):format(it.date, it.text, ref(it)))
  end

  local inbox_path = config.path("inbox", root)
  local inbox_open = vim.tbl_filter(function(it)
    return it.kind == "task" and not it.checked and it.file == inbox_path and it.section ~= "someday"
  end, items)
  local aging = vim.tbl_filter(function(it)
    return it.date ~= nil and it.date < p.start
  end, inbox_open)
  table.insert(out, "")
  table.insert(out, ("### INBOX items from before this period (%d)"):format(#aging))
  for _, it in ipairs(aging) do
    table.insert(out, ("- %s %s"):format(it.date, it.text))
  end

  local known = {}
  for _, name in ipairs(require("logpose.search").projects(root, all)) do
    known[name] = true
  end
  local unfiled = vim.tbl_filter(function(it)
    for _, tag in ipairs(it.tags) do
      if known[tag] then
        return false
      end
    end
    return true
  end, inbox_open)
  table.insert(out, "")
  table.insert(out, ("### INBOX items without a project (%d)"):format(#unfiled))
  for _, it in ipairs(unfiled) do
    table.insert(out, "- " .. it.text)
  end
  return out
end

--- Parse `[week|sprint] [offset] [filters…]`.
---@param args string[]
---@return string kind, string spec, string[] filters
function M.parse_args(args)
  args = vim.list_extend({}, args)
  local kind = config.get().period.kind
  if args[1] == "week" or args[1] == "sprint" then
    kind = table.remove(args, 1)
  end
  local spec = "current"
  if args[1] and (args[1]:match("^[+-]?%d+$") or date.is_iso(args[1]) or args[1] == "current") then
    spec = table.remove(args, 1)
    if spec == "0" or spec == "+0" or spec == "-0" then
      spec = "current"
    elseif kind == "week" and spec:match("^%d+$") then
      error("logpose: week offsets need a sign (-1, +1)", 0)
    end
  end
  return kind, spec, args
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local kind, spec, filters = M.parse_args(opts.args)
  query.parse(filters)
  config.with_root(ui.safely(function(root)
    local today = date.today()
    local p, err = require("logpose.period").resolve(kind, spec, today)
    if not p then
      error(err, 0)
    end
    local name = p.key
      .. (#filters > 0 and ("-" .. require("logpose.util.text").slugify(table.concat(filters, " "))) or "")
    local dest = fs.join(config.path("reports", root), name .. ".md")
    local lines = M.build(root, p, filters, today, dest)
    if opts.bang then
      local ok, werr = fs.write_file(dest, table.concat(lines, "\n") .. "\n")
      if not ok then
        error(werr, 0)
      end
      vim.cmd.edit(vim.fn.fnameescape(dest))
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "markdown"
    pcall(vim.api.nvim_buf_set_name, buf, "logpose://report/" .. name)
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
  end))
end

function M.complete(arglead, args)
  if #args == 0 then
    return { "week", "sprint", "-1", "current" }
  end
  if #args == 1 and (args[1] == "week" or args[1] == "sprint") then
    return { "current", "-1", "-2", "+1" }
  end
  return require("logpose.search").complete(arglead, { "tasks" })
end

return M

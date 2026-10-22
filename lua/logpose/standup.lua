--- Standup prep: new daily notes start from the previous one, and `:Logpose standup` shows
--- Yesterday / Today / Blockers ready to read out.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local markdown = require("logpose.markdown")
local todos = require("logpose.todos")
local ui = require("logpose.util.ui")

local M = {}

--- Line range (first body line, last body line) of `## <name>` in `lines`, or nil.
---@param lines string[]
---@param name string
---@return integer? first, integer? last, integer? heading
function M.section_range(lines, name)
  local want = name:lower()
  for i, line in ipairs(lines) do
    local h = line:match("^##%s+(.-)%s*$")
    if h and h:lower() == want then
      local last = #lines
      for j = i + 1, #lines do
        if lines[j]:match("^##?%s") then
          last = j - 1
          break
        end
      end
      return i + 1, last, i
    end
  end
  return nil
end

--- Body of `## <name>` without surrounding blank lines ({} if missing).
---@param lines string[]
---@param name string
---@return string[]
function M.section(lines, name)
  local first, last = M.section_range(lines, name)
  if not first then
    return {}
  end
  return markdown.trim_blank(vim.list_slice(lines, first, last))
end

--- Most recent daily note before `iso`.
---@param root string
---@param iso string
---@return string? path, string? date
function M.previous_daily(root, iso)
  local daily = require("logpose.notes.daily")
  local dir = config.path("daily", root)
  local best
  if fs.is_dir(dir) then
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" then
        local d = daily.date_of(name)
        if d and d < iso and (not best or d > best) then
          best = d
        end
      end
    end
  end
  if not best then
    return nil
  end
  return daily.path(best, root), best
end

---@class logpose.Prefill
---@field yesterday string[]  lines for ## Yesterday
---@field today string[]      open to-dos carried into ## Today
---@field carried integer[]   their line numbers in the previous note

--- What a new daily note takes from the previous one.
---@param prev_lines string[]
---@return logpose.Prefill
function M.prefill(prev_lines)
  local opts = config.get().standup
  local first, last = M.section_range(prev_lines, opts.sections.today)
  local yesterday, today, carried = {}, {}, {}
  -- the `→ [[task]]` line under a to-do made into a task goes where the to-do goes
  local link_rows = {}
  for _, t in ipairs(todos.linked(prev_lines)) do
    link_rows[t.link_row] = t.row
  end
  local moved = {}
  if first then
    for lnum = first, last do
      local line = prev_lines[lnum]
      local todo = todos.parse(line)
      if todo then
        if todo.checked then
          table.insert(yesterday, todo.indent .. "- " .. todo.text)
        elseif vim.trim(todo.text) ~= "" and opts.carry_forward then
          table.insert(today, todo.indent .. "- [ ] " .. todo.text)
          table.insert(carried, lnum)
          moved[lnum] = true
        end
      elseif link_rows[lnum] and moved[link_rows[lnum]] then
        table.insert(today, line)
      elseif vim.trim(line) ~= "" and not line:match("^%s*[-*+]%s+%[>%]") then
        table.insert(yesterday, line) -- notes and plain bullets
      end
    end
  end
  return { yesterday = yesterday, today = today, carried = carried }
end

--- Insert `items` right after the `## <name>` heading of `lines`. Returns the heading's line
--- number (or nil when the section is missing).
---@param lines string[]
---@param name string
---@param items string[]
---@return integer?
local function insert_after_heading(lines, name, items)
  local _, _, heading = M.section_range(lines, name)
  if not heading or #items == 0 then
    return heading
  end
  for i, item in ipairs(items) do
    table.insert(lines, heading + i, item)
  end
  return heading
end

--- Apply the prefill to a freshly rendered daily note.
---@param text string
---@param cursor integer[]
---@param fill logpose.Prefill
---@return string text, integer[] cursor
function M.apply(text, cursor, fill)
  local sections = config.get().standup.sections
  local lines = vim.split(text, "\n", { plain = true })
  cursor = { cursor[1], cursor[2] }
  for _, part in ipairs({ { sections.yesterday, fill.yesterday }, { sections.today, fill.today } }) do
    local heading = insert_after_heading(lines, part[1], part[2])
    if heading and #part[2] > 0 and cursor[1] > heading then
      cursor[1] = cursor[1] + #part[2]
    end
  end
  return table.concat(lines, "\n"), cursor
end

--- Mark carried tasks `- [>]` in the previous daily note.
---@param path string
---@param rows integer[]
function M.mark_carried(path, rows)
  if #rows == 0 or not config.get().standup.mark_carried then
    return
  end
  local ok, err = fs.update_lines(path, function(lines)
    local touched = false
    for _, lnum in ipairs(rows) do
      local line = lines[lnum]
      if line and line:match("^%s*[-*+]%s+%[ %]") then
        lines[lnum] = line:gsub("%[ %]", "[>]", 1)
        touched = true
      end
    end
    return touched and lines or nil
  end)
  if not ok then
    require("logpose.util.ui").notify(
      "logpose: couldn't mark carried to-dos in the previous daily note: " .. err,
      vim.log.levels.WARN
    )
  end
end

--- Prefill hook for a new daily note (called by notes/daily.lua before writing).
---@param root string
---@param iso string
---@param text string
---@param cursor integer[]
---@return string text, integer[] cursor, fun()? after_write
function M.prepare(root, iso, text, cursor)
  local prev_path = M.previous_daily(root, iso)
  if not prev_path then
    return text, cursor
  end
  local prev_lines = fs.current_lines(prev_path) -- an unsaved buffer's, the lines marked later
  if not prev_lines then
    return text, cursor
  end
  local fill = M.prefill(prev_lines)
  local new_text, new_cursor = M.apply(text, cursor, fill)
  return new_text, new_cursor, function()
    M.mark_carried(prev_path, fill.carried)
  end
end

--- Group list items by project tag (#project); returns lines with `### project` headings.
---@param items string[]
---@param projects string[]
---@return string[]
local function group(items, projects)
  local known = {}
  for _, p in ipairs(projects) do
    known[p] = true
  end
  local groups, order, other = {}, {}, {}
  for _, line in ipairs(items) do
    local proj
    for _, tag in ipairs(require("logpose.index").tags_in(line)) do
      if known[tag] then
        proj = tag
        break
      end
    end
    if proj then
      if not groups[proj] then
        groups[proj] = {}
        table.insert(order, proj)
      end
      table.insert(groups[proj], line)
    else
      table.insert(other, line)
    end
  end
  if #order == 0 then
    return items
  end
  table.sort(order)
  local out = {}
  for _, proj in ipairs(order) do
    table.insert(out, "### " .. proj)
    vim.list_extend(out, groups[proj])
  end
  if #other > 0 then
    table.insert(out, "### other")
    vim.list_extend(out, other)
  end
  return out
end

--- Task lines for each standup section: done since the previous workday, in progress,
--- blocked. Each line carries `#project` so grouping works.
---@param root string
---@param iso string
---@return table<string, string[]>
function M.board_items(root, iso)
  local out = { yesterday = {}, today = {}, blockers = {} }
  local cfg = config.get().board
  local since = date.prev_workday(iso, config.get().workdays)
  local tasks = vim.tbl_filter(function(it)
    return it.kind == "task" and not it.archived
  end, require("logpose.index").build(root))
  table.sort(tasks, function(a, b)
    return a.file < b.file
  end)
  for _, it in ipairs(tasks) do
    local tag = it.project and (" #" .. it.project) or ""
    if it.status == cfg.done then
      if it.done_date and it.done_date >= since and it.done_date < iso then
        table.insert(out.yesterday, "- [x] " .. it.text .. tag)
      end
    else
      if it.status == cfg.start then
        table.insert(out.today, "- [ ] " .. it.text .. tag)
      end
      if it.blocked then
        local reason = it.blocked == "yes" and "" or (": " .. it.blocked)
        table.insert(out.blockers, "- " .. it.text .. reason .. tag)
      end
    end
  end
  return out
end

--- Standup text for the daily note of `iso`, plus the board's task files.
---@param root string
---@param iso string
---@return string[]? lines, string? err
function M.render(root, iso)
  local daily = require("logpose.notes.daily")
  local path = daily.path(iso, root)
  local buf = fs.find_buf(path)
  local lines = buf and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or fs.read_lines(path)
  local board = M.board_items(root, iso)
  if not lines then
    if #board.yesterday + #board.today + #board.blockers == 0 then
      return nil, ("logpose: no daily note for %s; run :Logpose daily"):format(iso)
    end
    lines = {}
  end
  local opts = config.get().standup
  local projects = {}
  if opts.group_by_project then
    local search = require("logpose.search")
    projects = search.projects(root, require("logpose.index").build(root))
  end
  local out = { "# Standup " .. iso }
  for _, key in ipairs({ "yesterday", "today", "blockers" }) do
    local name = opts.sections[key]
    local items = M.section(lines, name)
    for _, line in ipairs(board[key]) do
      if not vim.tbl_contains(items, line) then
        table.insert(items, line)
      end
    end
    table.insert(out, "")
    table.insert(out, "## " .. name)
    if #items == 0 then
      table.insert(out, "- (none)")
    else
      vim.list_extend(out, opts.group_by_project and group(items, projects) or items)
    end
  end
  return (require("logpose.markdown").tidy(out))
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local iso = opts.args[1]
  if iso == nil or iso == "today" then
    iso = date.today()
  elseif not date.is_iso(iso) then
    error(("logpose: invalid date %q (use YYYY-MM-DD)"):format(iso), 0)
  end
  config.with_root(ui.safely(function(root)
    local lines, err = M.render(root, iso)
    if not lines then
      require("logpose.util.ui").notify(err, vim.log.levels.WARN)
      return
    end
    ui.scratch(lines, {
      name = "logpose://standup/" .. iso,
      filetype = "markdown",
      height = math.min(#lines + 1, 25),
      locked = true,
    })
  end))
end

return M

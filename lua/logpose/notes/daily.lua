--- Daily notes: `:Logpose daily [today|prev|next|YYYY-MM-DD]`. A scratchpad for the day: write
--- anything; meetings link themselves under `## Meetings`. Today's new note starts with the open
--- to-dos of the previous one under `## To-dos` (marked `- [>]` there, so each lives in one place)
--- and its `## Blockers`, which hold until you remove them.
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

--- The dates of the daily notes there are, oldest first.
---@param root string
---@return string[]
function M.dates(root)
  local dir = config.path("daily", root)
  local out = {}
  if fs.is_dir(dir) then
    for name, kind in vim.fs.dir(dir) do
      local d = (kind == "file" or kind == "link") and M.date_of(name)
      if d then
        table.insert(out, d)
      end
    end
  end
  table.sort(out)
  return out
end

--- Is `arg` something `:Logpose daily` takes?
---@param arg? string
local function check_arg(arg)
  if arg == nil or arg == "" or arg == "today" or arg == "prev" or arg == "next" or date.is_iso(arg) then
    return
  end
  error(("logpose: invalid date %q (use today, prev, next or YYYY-MM-DD)"):format(arg), 0)
end

--- Turn a command argument into a date. `prev`/`next` go to the daily note before or after
--- `base` (the one in the current buffer, or today), among the notes there are and today's, so
--- they never make a note for a day you didn't write one.
---@param arg? string
---@param root string
---@param base? string
---@return string
function M.resolve_date(arg, root, base)
  check_arg(arg)
  local today = date.today()
  if arg == nil or arg == "" or arg == "today" then
    return today
  end
  if arg == "prev" or arg == "next" then
    base = base or today
    local stops = M.dates(root)
    if not vim.tbl_contains(stops, today) then
      table.insert(stops, today) -- today's note is always there to go to
      table.sort(stops)
    end
    local pick
    for _, d in ipairs(stops) do
      if arg == "prev" and d < base then
        pick = d
      elseif arg == "next" and d > base and not pick then
        pick = d
      end
    end
    if not pick then
      error(("logpose: no daily note %s %s"):format(arg == "prev" and "before" or "after", date.short(base, today)), 0)
    end
    return pick
  end
  return arg
end

--- Most recent daily note before `iso`.
---@param root string
---@param iso string
---@return string? path, string? date
function M.previous(root, iso)
  local best
  for _, d in ipairs(M.dates(root)) do
    if d < iso then
      best = d
    end
  end
  if not best then
    return nil
  end
  return M.path(best, root), best
end

--- The open to-dos of a note to carry over: their lines (with the `→ [[task]]` line of a to-do
--- made into a task) and the rows to mark `[>]`.
---@param lines string[]
---@return string[] carried, integer[] rows
function M.open_todos(lines)
  local todos = require("logpose.todos")
  local code = require("logpose.markdown").code_rows(lines) -- a checklist in a code block is code
  local link_of = {}
  for _, t in ipairs(todos.linked(lines)) do
    link_of[t.row] = t.link_text
  end
  local out, rows = {}, {}
  -- A carried to-do stays under the carried to-dos it was nested in; under one that stays behind
  -- (checked, or a plain item) it moves up a level. The list items above the line, innermost last:
  local above = {} ---@type { indent: integer, carried: boolean }[]
  for i, line in ipairs(lines) do
    local indent, rest = line:match("^(%s*)(.-)%s*$")
    local width = #(indent:gsub("\t", "    "))
    local item = rest:match("^[-*+]%s") or rest:match("^%d+[.)]%s")
    if code[i] or rest == "" then
      -- neither ends a list nor is in one
    elseif line:match("^#+%s") then
      above = {}
    elseif item or width == 0 then
      while #above > 0 and above[#above].indent >= width do
        table.remove(above)
      end
    end
    if item and not code[i] then
      local t = todos.parse(line)
      local carried = t ~= nil and not t.checked and vim.trim(t.text) ~= ""
      if carried then
        local depth = 0
        for _, a in ipairs(above) do
          depth = depth + (a.carried and 1 or 0)
        end
        local pad = string.rep("  ", depth)
        table.insert(out, pad .. "- [ ] " .. t.text)
        if link_of[i] then
          table.insert(out, pad .. "  " .. link_of[i])
        end
        table.insert(rows, i)
      end
      table.insert(above, { indent = width, carried = carried })
    end
  end
  return out, rows
end

--- The lines under a note's `## Blockers` heading (they hold until you remove them). A heading
--- in a code block is code; a code block under the heading comes along whole.
---@param lines string[]
---@return string[]
function M.blockers(lines)
  local code = require("logpose.markdown").code_rows(lines)
  local out, inside = {}, false
  for i, l in ipairs(lines) do
    local h2 = not code[i] and l:match("^##%s+(.-)%s*$") or nil
    if h2 or (not code[i] and l:match("^#%s")) then
      inside = h2 ~= nil and h2:lower() == "blockers"
    elseif inside and (code[i] or vim.trim(l) ~= "") then
      table.insert(out, l)
    end
  end
  return out
end

--- Links to the meetings of `iso`, as they go under a daily note's `## Meetings`.
---@param root string
---@param path string the daily note
---@param iso string
---@return string[]
function M.meeting_items(root, path, iso)
  local meetings = {}
  for _, it in ipairs(require("logpose.index").build(root)) do
    if it.kind == "note" and it.file_type == "meeting" and it.date == iso then
      table.insert(meetings, it)
    end
  end
  table.sort(meetings, function(a, b)
    return a.file < b.file
  end)
  local meeting = require("logpose.notes.meeting")
  return vim.tbl_map(function(it)
    return meeting.daily_item(root, path, it.file, it.title, it.project)
  end, meetings)
end

--- Put sections (`## To-dos`, `## Blockers`, `## Meetings`) right after the note's title; empty
--- ones are left out.
---@param text string
---@param cursor integer[]
---@param sections { [1]: string, [2]: string[] }[]
---@return string text, integer[] cursor
local function with_sections(text, cursor, sections)
  local lines = vim.split(text, "\n", { plain = true })
  local at = 0
  for i, l in ipairs(lines) do
    if l:match("^#%s") then
      at = i
      break
    end
  end
  local block = {}
  for _, sec in ipairs(sections) do
    if #sec[2] > 0 then
      vim.list_extend(block, { "", "## " .. sec[1], "" })
      vim.list_extend(block, sec[2])
    end
  end
  for k, l in ipairs(block) do
    table.insert(lines, at + k, l)
  end
  cursor = { cursor[1] + (cursor[1] > at and #block or 0), cursor[2] }
  return table.concat(lines, "\n"), cursor
end

--- Mark carried to-dos `- [>]` in the previous note.
---@param path string
---@param rows integer[]
local function mark_carried(path, rows)
  if #rows == 0 or not config.get().daily.mark_carried then
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
    ui.notify("logpose: couldn't mark carried to-dos in the previous daily note: " .. err, vim.log.levels.WARN)
  end
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
  local text, cursor = rendered.text, rendered.cursor or { 1, 0 }
  -- the previous note's open to-dos and blockers come along, into today's note only: a note made
  -- ahead of time (or after the fact) would take them from the day they belong to
  local after_write
  local prev = config.get().daily.carry_over and iso == date.today() and M.previous(root, iso)
  local prev_lines = prev and fs.current_lines(prev)
  local sections = {}
  if prev_lines then
    local carried, rows = M.open_todos(prev_lines)
    vim.list_extend(sections, { { "To-dos", carried }, { "Blockers", M.blockers(prev_lines) } })
    if #rows > 0 then
      after_write = function()
        mark_carried(prev, rows)
      end
    end
  end
  -- the day's meetings, planned before its note was made, are linked from it
  table.insert(sections, { "Meetings", M.meeting_items(root, path, iso) })
  text, cursor = with_sections(text, cursor, sections)
  -- the notes before and after it, linked from the frontmatter
  local chain = require("logpose.notes.chain")
  local links, prev_link, next_link = {}, nil, nil
  if config.get().daily.links then
    prev_link, next_link = chain.daily_neighbours(root, iso)
    links = { previous = chain.value(root, path, prev_link), next = chain.value(root, path, next_link) }
  end
  local lines = vim.split(text, "\n", { plain = true })
  local before = #lines
  if lines[1] == "---" then
    lines = chain.apply(lines, links) -- the template's own frontmatter (it keeps its timestamps)
  else
    -- No title here: the note's `# heading` stays its title (markdownlint MD025).
    local fmt = require("logpose.frontmatter")
    local fm = { "---" }
    for _, key in ipairs({ "previous", "next" }) do
      if links[key] then
        table.insert(fm, fmt.line(key, links[key]))
      end
    end
    vim.list_extend(fm, require("logpose.timestamps").lines())
    if #fm > 1 then
      table.insert(fm, "---")
      lines = vim.list_extend(fm, lines)
    end
  end
  cursor = { cursor[1] + #lines - before, cursor[2] }
  text, cursor = require("logpose.markdown").tidy_text(table.concat(lines, "\n"), cursor)
  local ok, err = fs.write_file(path, text, { tidy = true })
  if not ok then
    error(err, 0)
  end
  if after_write then
    after_write()
  end
  if prev_link or next_link then
    chain.link_neighbours(root, { file = path, label = chain.daily_label(iso) }, prev_link, next_link)
  end
  return path, true, cursor
end

--- Create (if needed) and open the daily note for `iso`.
---@param iso string
---@param root string
function M.open_date(iso, root)
  local path, created, cursor = M.ensure(iso, root)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if created and cursor then
    -- the cursor goes below the last heading: a line to write on (the file keeps no trailing blank)
    local count = vim.api.nvim_buf_line_count(0)
    local last = vim.api.nvim_buf_get_lines(0, count - 1, count, false)[1] or ""
    if cursor[1] >= count and last:match("^#+%s") then
      vim.api.nvim_buf_set_lines(0, count, count, false, { "", "" })
      vim.bo.modified = false
      cursor = { count + 2, 0 }
      -- saved untouched, those lines go again (no trailing blank lines: markdownlint MD012)
      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = vim.api.nvim_get_current_buf(),
        callback = function(ev)
          local n = vim.api.nvim_buf_line_count(ev.buf)
          local last_text = n
          while
            last_text > 1 and vim.trim(vim.api.nvim_buf_get_lines(ev.buf, last_text - 1, last_text, false)[1]) == ""
          do
            last_text = last_text - 1
          end
          if last_text < n then
            pcall(vim.cmd.undojoin)
            vim.api.nvim_buf_set_lines(ev.buf, last_text, n, false, {})
          end
        end,
      })
    end
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
end

--- Create (if needed) and open the daily note. Offers onboarding when there's no journal yet.
---@param arg? string today|prev|next|YYYY-MM-DD
function M.open(arg)
  check_arg(arg)
  -- read now: `prev`/`next` go from the daily note in the current buffer
  local base = M.date_of(vim.api.nvim_buf_get_name(0))
  config.with_root(ui.safely(function(root)
    M.open_date(M.resolve_date(arg, root, base), root)
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

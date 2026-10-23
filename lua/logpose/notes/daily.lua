--- Daily notes: `:Logpose daily [today|prev|next|YYYY-MM-DD]`. A scratchpad for the day: write
--- anything; meetings link themselves under `## Meetings`. A new note starts with the open to-dos
--- of the previous one under `## To-dos` (marked `- [>]` there, so each lives in one place) and its
--- `## Blockers`, which hold until you remove them.
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

--- Most recent daily note before `iso`.
---@param root string
---@param iso string
---@return string? path, string? date
function M.previous(root, iso)
  local dir = config.path("daily", root)
  local best
  if fs.is_dir(dir) then
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" then
        local d = M.date_of(name)
        if d and d < iso and (not best or d > best) then
          best = d
        end
      end
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
  local link_of = {}
  for _, t in ipairs(todos.linked(lines)) do
    link_of[t.row] = t.link_text
  end
  local out, rows = {}, {}
  for i, line in ipairs(lines) do
    local t = todos.parse(line)
    if t and not t.checked and vim.trim(t.text) ~= "" then
      table.insert(out, "- [ ] " .. t.text)
      if link_of[i] then
        table.insert(out, "  " .. link_of[i])
      end
      table.insert(rows, i)
    end
  end
  return out, rows
end

--- The lines under a note's `## Blockers` heading (they hold until you remove them).
---@param lines string[]
---@return string[]
function M.blockers(lines)
  local out, inside = {}, false
  for _, l in ipairs(lines) do
    local h = l:match("^##%s+(.-)%s*$")
    if h or l:match("^#%s") then
      inside = h ~= nil and h:lower() == "blockers"
    elseif inside and vim.trim(l) ~= "" then
      table.insert(out, l)
    end
  end
  return out
end

--- Put carried sections (`## To-dos`, `## Blockers`) right after the note's title.
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
  -- the previous note's open to-dos and blockers come along
  local after_write
  local prev = config.get().daily.carry_over and M.previous(root, iso)
  local prev_lines = prev and fs.current_lines(prev)
  if prev_lines then
    local carried, rows = M.open_todos(prev_lines)
    text, cursor = with_sections(text, cursor, { { "To-dos", carried }, { "Blockers", M.blockers(prev_lines) } })
    if #rows > 0 then
      after_write = function()
        mark_carried(prev, rows)
      end
    end
  end
  local stamps = require("logpose.timestamps").lines()
  if #stamps > 0 and text:sub(1, 4) ~= "---\n" then
    -- No title here: the note's `# heading` stays its title (markdownlint MD025).
    local fm = vim.list_extend({ "---" }, stamps)
    table.insert(fm, "---")
    text = table.concat(fm, "\n") .. "\n" .. text
    cursor = cursor and { cursor[1] + #fm, cursor[2] } or cursor
  end
  text, cursor = require("logpose.markdown").tidy_text(text, cursor)
  local ok, err = fs.write_file(path, text, { tidy = true })
  if not ok then
    error(err, 0)
  end
  if after_write then
    after_write()
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

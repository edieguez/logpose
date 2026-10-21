--- To-dos: checkboxes (`- [ ] …`) inside notes and task files. A to-do belongs to the note it's
--- written in; it isn't a task. Tasks are task files on the board, and `:Logpose promote` turns a
--- to-do into one. `:Logpose check` checks to-dos off.
local ui = require("logpose.util.ui")

local M = {}

--- Parse a checkbox line.
---@param line string
---@return { indent: string, checked: boolean, text: string }?
function M.parse(line)
  local indent, mark, rest = line:match("^(%s*)[-*+]%s+%[([ xX])%]%s?(.*)$")
  if not indent then
    return nil
  end
  return { indent = indent, checked = mark ~= " ", text = rest }
end

--- Check off the to-dos on rows `line1`..`line2` of `buf`, or uncheck them when every one is
--- already checked. Edited through the API, so `u` undoes it.
---@param buf integer
---@param line1 integer
---@param line2 integer
---@return { checked: integer, unchecked: integer, skipped: integer }
function M.check(buf, line1, line2)
  local lines = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, false)
  local rows, all_checked = {}, true
  for i, line in ipairs(lines) do
    local t = M.parse(line)
    if t then
      table.insert(rows, { row = line1 + i - 1, checked = t.checked })
      all_checked = all_checked and t.checked
    end
  end
  local out = { checked = 0, unchecked = 0, skipped = #lines - #rows }
  for _, r in ipairs(rows) do
    local line = vim.api.nvim_buf_get_lines(buf, r.row - 1, r.row, false)[1]
    local new
    if all_checked then
      new = line:gsub("%[[xX]%]", "[ ]", 1)
      out.unchecked = out.unchecked + 1
    elseif not r.checked then
      new = line:gsub("%[ %]", "[x]", 1)
      out.checked = out.checked + 1
    end
    if new then
      vim.api.nvim_buf_set_lines(buf, r.row - 1, r.row, false, { new })
    end
  end
  return out
end

---@param n integer
---@return string
local function todos(n)
  return ("%d to-do%s"):format(n, n == 1 and "" or "s")
end

--- `:Logpose check`: check off the to-do on this line (or the selected lines); again to uncheck.
---@param opts logpose.CommandOpts
function M.check_command(opts)
  local line1, line2 = opts.line1, opts.line2
  if opts.range == 0 or not line1 or line1 == 0 then
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end
  local r = M.check(vim.api.nvim_get_current_buf(), line1, line2)
  if r.checked + r.unchecked == 0 then
    error("logpose: no to-do here (a `- [ ]` line)", 0)
  end
  local parts = {}
  if r.checked > 0 then
    table.insert(parts, todos(r.checked) .. " checked")
  end
  if r.unchecked > 0 then
    table.insert(parts, todos(r.unchecked) .. " unchecked")
  end
  if r.skipped > 0 then
    table.insert(parts, ("skipped %d other line%s"):format(r.skipped, r.skipped == 1 and "" or "s"))
  end
  ui.notify("logpose: " .. table.concat(parts, ", "), vim.log.levels.INFO)
end

--- `:Logpose promote`: turn the to-do on the cursor line into a task (a task file in
--- `tasks.promote_status`, or Done if it was checked). The two link to each other: the to-do
--- keeps its text and gains a `→ [[task]]` line under it, the task gets a `From:` link back.
---@param root string
---@return string path the new task file
function M.promote(root)
  local config = require("logpose.config")
  local taskfile = require("logpose.taskfile")
  local buf = vim.api.nvim_get_current_buf()
  local note = vim.api.nvim_buf_get_name(buf)
  if note == "" or vim.bo[buf].buftype ~= "" then
    error("logpose: :Logpose promote works on a to-do in a journal note", 0)
  end
  if taskfile.is_task_file(note, root) and not M.parse(vim.api.nvim_get_current_line()) then
    error("logpose: this is a task already; promote works on a to-do in a note", 0)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  local todo = M.parse(line)
  if not todo or vim.trim(todo.text) == "" then
    error("logpose: no to-do on this line (a `- [ ]` line)", 0)
  end
  local index = require("logpose.index")
  local note_item = index.index_lines(note, vim.api.nvim_buf_get_lines(buf, 0, -1, false), root)[1]
  local project = note_item.project or require("logpose.project").resolve(root)
  local title, tags, due, explicit = taskfile.from_text(todo.text)
  if explicit ~= nil then
    project = explicit or nil
  end
  local link = require("logpose.link")
  local path = taskfile.path_for(root, title)
  local status = todo.checked and config.get().board.done or config.get().tasks.promote_status
  taskfile.create(root, {
    path = path,
    title = title,
    status = status,
    project = project,
    tags = tags,
    due = due,
    body = { "From: " .. link.make(path, note, note_item.title, root) },
  })
  local was_modified = vim.bo[buf].modified
  -- the to-do keeps its words (its owner and due date keep it in :Logpose actions) and links to
  -- the task, which links back with `From:`
  -- (on a line of its own under the item, so long lines stay within markdownlint's limit)
  local cont = string.rep(" ", #todo.indent + 2) .. "→ " .. link.make(note, path, "task", root)
  vim.api.nvim_buf_set_lines(buf, row, row, false, { cont })
  if not was_modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent write")
    end)
  end
  ui.notify(
    ("logpose: promoted to a task: %s (%s · %s)"):format(
      link.relpath(root, path),
      taskfile.label(status),
      project or "no project"
    ),
    vim.log.levels.INFO
  )
  return path
end

--- `:Logpose promote`: on a to-do, a task; in a task file (not on one of its to-dos), the
--- task's write-up (or the selected lines) becomes a note.
---@param opts logpose.CommandOpts
function M.promote_command(opts)
  require("logpose.config").with_root(ui.safely(function(root)
    local path = vim.api.nvim_buf_get_name(0)
    local taskfile = require("logpose.taskfile")
    local on_todo = M.parse(vim.api.nvim_get_current_line()) ~= nil and (opts.range or 0) == 0
    if path ~= "" and taskfile.is_task_file(path, root) and not on_todo then
      require("logpose.notes.from_task").command(root, require("logpose.util.fs").normalize(path), opts)
      return
    end
    M.promote(root)
  end))
end

return M

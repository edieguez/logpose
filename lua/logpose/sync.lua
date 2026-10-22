--- A to-do made into a task (`:Logpose promote`) and its task stay in step, both ways: the task
--- done checks the to-do, the to-do checked moves the task to Done (asking first when the task
--- hasn't started), and reopening either reopens the other. The link is the `→ [[task]]` line
--- under the to-do. Notes are edited without bumping `modified:`; a note with unsaved changes is
--- edited in its buffer.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

--- Tasks you chose to leave open when checking their to-do (not asked again this session).
---@type table<string, boolean>
M.declined = {}

--- Current lines of a file: the ones `fs.update_lines` edits.
---@param path string
---@return string[]
local function lines_of(path)
  return fs.current_lines(path) or {}
end

--- Journal files by lowercase name, for short wiki links.
---@param root string
---@return table<string, string[]>
local function by_name(root)
  local index = require("logpose.index")
  local out = {}
  for _, it in ipairs(index.build(root)) do
    if index.is_file(it) then
      local stem = vim.fn.fnamemodify(it.file, ":t:r"):lower()
      out[stem] = out[stem] or {}
      table.insert(out[stem], it.file)
    end
  end
  return out
end

--- The task a linked to-do in `file` points at (nil when the link isn't to a task).
---@param root string
---@param file string
---@param link { target: string, style: string }
---@param names? table<string, string[]>
---@return string?
function M.task_of(root, file, link, names)
  local path = require("logpose.links").resolve(root, file, link, names or by_name(root))
  if path and require("logpose.taskfile").is_task_file(path, root) then
    return fs.normalize(path)
  end
  return nil
end

--- The to-dos made into `task`: { file, row, checked }.
---@param root string
---@param task string
---@return { file: string, row: integer, checked: boolean }[]
function M.todos_of(root, task)
  local todos = require("logpose.todos")
  task = fs.normalize(task)
  -- the notes holding to-dos made into tasks (from the index: only those links get resolved)
  local files, out = {}, {}
  for _, it in ipairs(require("logpose.index").build(root)) do
    if it.kind == "todo" and it.task_link and not files[it.file] then
      files[it.file] = true
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    -- and notes with unsaved changes (a to-do promoted but not saved yet)
    if vim.bo[buf].modified and vim.api.nvim_buf_get_name(buf):match("%.md$") then
      files[fs.normalize(vim.api.nvim_buf_get_name(buf))] = true
    end
  end
  local names
  for file in pairs(files) do
    for _, t in ipairs(todos.linked(lines_of(file))) do
      names = names or by_name(root)
      if M.task_of(root, file, t.link, names) == task then
        table.insert(out, { file = file, row = t.row, checked = t.checked })
      end
    end
  end
  table.sort(out, function(a, b)
    return a.file == b.file and a.row < b.row or a.file < b.file
  end)
  return out
end

--- Is this status Done?
---@param status? string
---@return boolean
local function is_done(status)
  return status == config.get().board.done
end

--- Check (or uncheck) the to-dos made into `task`. Returns how many changed.
---@param root string
---@param task string
---@param done boolean
---@return integer
function M.set_todos(root, task, done)
  M.declined[fs.normalize(task)] = nil
  local by_file = {}
  for _, t in ipairs(M.todos_of(root, task)) do
    if t.checked ~= done then
      by_file[t.file] = by_file[t.file] or {}
      table.insert(by_file[t.file], t.row)
    end
  end
  local n, titles = 0, {}
  for file, rows in pairs(by_file) do
    local ok, err = fs.update_lines(file, function(lines)
      for _, row in ipairs(rows) do
        local line = lines[row]
        lines[row] = done and line:gsub("%[ %]", "[x]", 1) or line:gsub("%[[xX]%]", "[ ]", 1)
      end
      return lines
    end, { raw = true })
    if not ok then
      error(err, 0)
    end
    n = n + #rows
    local item = require("logpose.index").index_lines(file, lines_of(file), root)[1]
    table.insert(titles, item.title)
  end
  if n > 0 then
    require("logpose.index").clear_cache()
    table.sort(titles)
    ui.notify(
      ("logpose: %s its to-do in %s"):format(done and "checked" or "unchecked", table.concat(titles, ", ")),
      vim.log.levels.INFO
    )
  end
  return n
end

--- The column a done task goes back to: where it was before Done (from its log), else the
--- board's "started" column.
---@param lines string[]
---@return string
function M.reopen_status(lines)
  local taskfile = require("logpose.taskfile")
  local board = config.get().board
  local done_label = taskfile.label(board.done)
  local from
  for _, l in ipairs(lines) do
    local a, b = l:match("^%-%s+%d%d%d%d%-%d%d%-%d%d%s+%d%d?:%d%d:%s*(.-)%s*→%s*(.-)%s*$")
    if a and b == done_label then
      from = a
    end
  end
  for _, c in ipairs(taskfile.columns()) do
    if from and (c.label == from or c.key == from) and c.key ~= board.done then
      return c.key
    end
  end
  return board.start
end

--- A to-do made into `task` was checked (`checked`) or unchecked: bring the task along.
--- Checking it while the task hasn't started asks first.
---@param root string
---@param task string
---@param checked boolean
function M.todo_changed(root, task, checked)
  local taskfile = require("logpose.taskfile")
  task = fs.normalize(task)
  if not fs.exists(task) then
    return
  end
  local lines = lines_of(task)
  local t = taskfile.parse(task, lines, root)
  local board = config.get().board
  if checked == is_done(t.status) then
    return
  end
  local function move(status)
    taskfile.set_status(task, status)
    ui.notify(("logpose: moved %q to %s"):format(t.title, taskfile.label(status)), vim.log.levels.INFO)
  end
  if not checked then
    return move(M.reopen_status(lines))
  end
  local started = taskfile.column_index(board.start) or 1
  if (taskfile.column_index(t.status) or 1) >= started then
    return move(board.done)
  end
  if M.declined[task] then
    return
  end
  local yes = ("Move it to %s"):format(taskfile.label(board.done))
  local no = ("Leave it in %s"):format(taskfile.label(t.status))
  vim.ui.select(
    { yes, no },
    { prompt = ("%q hasn't started (%s). Done too?"):format(t.title, taskfile.label(t.status)) },
    ui.safely(function(choice)
      if choice == yes then
        move(board.done)
      elseif choice == no then
        M.declined[task] = true
      end
    end)
  )
end

--- After to-dos in `file` changed: the rows (to-dos made into tasks) and their new state.
---@param root string
---@param file string
---@param changes { link: table, checked: boolean }[]
function M.todos_changed(root, file, changes)
  local names = by_name(root)
  local seen = {}
  for _, c in ipairs(changes) do
    local task = M.task_of(root, file, c.link, names)
    if task and not seen[task] then
      seen[task] = true
      M.todo_changed(root, task, c.checked)
    end
  end
end

--- Before a journal file is saved: what was changed by hand. A task's status in or out of Done
--- updates its to-dos; to-dos made into tasks checked or unchecked update their tasks. Runs
--- after the save (scheduled), comparing with the file on disk.
---@param buf integer
function M.on_write(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local root = config.resolve_root()
  if not root or path == "" or not vim.bo[buf].modified then
    return
  end
  path = fs.normalize(path)
  if not vim.startswith(path, fs.normalize(root) .. "/") or not fs.exists(path) then
    return
  end
  local old = fs.read_lines(path) or {}
  local new = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local taskfile = require("logpose.taskfile")
  if taskfile.is_task_file(path, root) then
    local index = require("logpose.index")
    local was, now = index.frontmatter(old).status, index.frontmatter(new).status
    if is_done(was) ~= is_done(now) then
      local done = is_done(now)
      vim.schedule(ui.safely(function()
        M.set_todos(root, path, done)
      end))
    end
  end
  local todos = require("logpose.todos")
  local before = {}
  for _, t in ipairs(todos.linked(old)) do
    before[t.link_text] = t.checked
  end
  local changes = {}
  for _, t in ipairs(todos.linked(new)) do
    if before[t.link_text] ~= nil and before[t.link_text] ~= t.checked then
      table.insert(changes, { link = t.link, checked = t.checked })
    end
  end
  if #changes > 0 then
    vim.schedule(ui.safely(function()
      M.todos_changed(root, path, changes)
    end))
  end
end

function M.setup_autocmd()
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("logpose.sync", { clear = true }),
    pattern = "*.md",
    callback = function(ev)
      local ok, err = pcall(M.on_write, ev.buf)
      if not ok then
        ui.notify(ui.message(err), vim.log.levels.WARN)
      end
    end,
  })
end

return M

--- From checkboxes to task files: `:Logpose migrate[!]` (INBOX -> task files) and
--- `:Logpose promote` (the checkbox under the cursor -> a task file it links to).
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")

local M = {}

---@class logpose.Migration
---@field task logpose.NewTask
---@field rows integer[] INBOX lines (1-based) the task and its indented notes came from
---@field lines string[] those lines as read, to check nothing moved

--- Open INBOX tasks as task-file specs. Indented lines under a task become its body.
---@param root string
---@param lines string[]
---@return logpose.Migration[]
function M.plan(root, lines)
  local markdown = require("logpose.markdown")
  local parse_task = require("logpose.tasks").parse_task
  local index = require("logpose.index")
  local known = {}
  for _, name in ipairs(require("logpose.search").projects(root, index.build(root))) do
    known[name] = true
  end
  local out = {}
  local section_date, someday = nil, false
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line:match("^##%s") then
      section_date = markdown.heading_date(line)
      someday = not section_date and line:lower():find("someday", 1, true) ~= nil
    end
    local task = parse_task(line)
    if task and not task.checked and vim.trim(task.text) ~= "" then
      local indent = #(line:match("^(%s*)"))
      local title, tags, due = taskfile.from_text(task.text)
      local project
      for n, tag in ipairs(tags) do
        if known[tag] then
          project = tag
          table.remove(tags, n)
          break
        end
      end
      if someday and not vim.tbl_contains(tags, "someday") then
        table.insert(tags, "someday")
      end
      local rows, raw, body = { i }, { line }, {}
      local j = i + 1
      while j <= #lines and lines[j]:match("^%s+%S") and #(lines[j]:match("^(%s*)")) > indent do
        table.insert(rows, j)
        table.insert(raw, lines[j])
        table.insert(body, (lines[j]:gsub("^" .. string.rep("%s", indent + 1) .. "%s?", "")))
        j = j + 1
      end
      table.insert(out, {
        task = {
          title = title,
          status = config.get().tasks.capture_status,
          project = project,
          tags = tags,
          due = due,
          created = section_date,
          body = body,
        },
        rows = rows,
        lines = raw,
      })
      i = j
    else
      i = i + 1
    end
  end
  return out
end

--- Create the task files and remove the migrated lines from INBOX.
---@param root string
---@param plan logpose.Migration[]
---@return string[] paths
function M.apply(root, plan)
  local inbox = config.path("inbox", root)
  local ok, err = fs.check_writable({ inbox })
  if not ok then
    error(err, 0)
  end
  local drop = {}
  for _, m in ipairs(plan) do
    for n, row in ipairs(m.rows) do
      drop[row] = m.lines[n]
    end
  end
  -- Check INBOX is still as planned before writing anything.
  local current = fs.read_lines(inbox) or {}
  for row, line in pairs(drop) do
    if current[row] ~= line then
      error("logpose: INBOX changed since the preview; run :Logpose migrate again", 0)
    end
  end
  local paths = {}
  for _, m in ipairs(plan) do
    table.insert(paths, (taskfile.create(root, m.task)))
  end
  local wrote, werr = fs.update_lines(inbox, function(lines)
    local kept = {}
    for row, line in ipairs(lines) do
      if drop[row] == nil then
        table.insert(kept, line)
      end
    end
    return kept
  end, { tidy = true })
  if not wrote then
    error(werr, 0)
  end
  require("logpose.index").clear_cache()
  return paths
end

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    local inbox = config.path("inbox", root)
    local lines = fs.read_lines(inbox)
    if not lines then
      vim.notify("logpose: no INBOX to migrate", vim.log.levels.INFO)
      return
    end
    local plan = M.plan(root, lines)
    if #plan == 0 then
      vim.notify("logpose: no open INBOX tasks to migrate", vim.log.levels.INFO)
      return
    end
    local label = taskfile.label(config.get().tasks.capture_status)
    local function run()
      local paths = M.apply(root, plan)
      vim.notify(
        ("logpose: migrated %d task%s to %s"):format(#paths, #paths == 1 and "" or "s", label),
        vim.log.levels.INFO
      )
    end
    if opts.bang then
      return run()
    end
    local preview = { ("Migrate %d INBOX task%s to %s:"):format(#plan, #plan == 1 and "" or "s", label), "" }
    for _, m in ipairs(plan) do
      local meta = {}
      if m.task.project then
        table.insert(meta, m.task.project)
      end
      if #m.task.tags > 0 then
        table.insert(meta, "#" .. table.concat(m.task.tags, " #"))
      end
      if m.task.due then
        table.insert(meta, "due " .. m.task.due)
      end
      if #m.task.body > 0 then
        table.insert(meta, ("+%d line%s"):format(#m.task.body, #m.task.body == 1 and "" or "s"))
      end
      table.insert(preview, "  " .. m.task.title .. (#meta > 0 and ("  (" .. table.concat(meta, " · ") .. ")") or ""))
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview)
    vim.bo[buf].bufhidden = "wipe"
    vim.cmd(("botright %dsplit"):format(math.min(#preview, 20)))
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.ui.select(
      { "Migrate", "Cancel" },
      { prompt = "Migrate INBOX?" },
      ui.safely(function(choice)
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if choice == "Migrate" then
          run()
        else
          vim.notify("logpose: cancelled", vim.log.levels.INFO)
        end
      end)
    )
  end))
end

--- Turn the checkbox on the cursor line into a task file and link to it.
---@param root string
function M.promote(root)
  local buf = vim.api.nvim_get_current_buf()
  local note = vim.api.nvim_buf_get_name(buf)
  if note == "" or vim.bo[buf].buftype ~= "" then
    error("logpose: :Logpose promote works on a journal note", 0)
  end
  if taskfile.is_task_file(note, root) then
    error("logpose: this is already a task file", 0)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  local task = require("logpose.tasks").parse_task(line)
  if not task or vim.trim(task.text) == "" then
    error("logpose: no checkbox on this line", 0)
  end
  local index = require("logpose.index")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local items = index.index_lines(note, lines, root)
  local note_item = items[1]
  local project = note_item.project or require("logpose.project").resolve(root)
  local title, tags, due = taskfile.from_text(task.text)
  local link = require("logpose.link")
  local path = taskfile.path_for(root, title)
  local status = task.checked and config.get().board.done or config.get().tasks.promote_status
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
  local prefix = line:match("^(%s*[-*+]%s+%[.%]%s+)")
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { prefix .. link.make(note, path, title, root) })
  if not was_modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent write")
    end)
  end
  vim.notify(
    ("logpose: promoted to %s (%s)"):format(link.relpath(root, path), taskfile.label(status)),
    vim.log.levels.INFO
  )
  return path
end

---@param _ logpose.CommandOpts
function M.promote_command(_)
  M.promote(config.root())
end

return M

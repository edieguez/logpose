--- `:Logpose archive[!]`: move done tasks from past periods (weeks or sprints) into
--- `tasks/archive/<period>/`, out of the board. Archived tasks still show up in search and reports.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local period = require("logpose.period")
local ui = require("logpose.util.ui")

local M = {}

---@class logpose.ArchivePlan
---@field root string
---@field current logpose.Period  the current period (kept)
---@field tasks { from: string, to: string, key: string }[]  done task files to move
---@field conflicts { to: string, from: string[], exists: boolean }[]  moves that would overwrite a file

--- Work out what to move, entirely in memory. Nothing is written.
---@param root string
---@param today string
---@return logpose.ArchivePlan
function M.plan(root, today)
  local current = period.of(today)
  local plan = { root = root, current = current, tasks = {}, conflicts = {} }
  local taskfile = require("logpose.taskfile")
  local done_status = config.get().board.done
  for _, t in ipairs(taskfile.list(root)) do
    if t.status == done_status and t.done and date.is_iso(t.done) then
      local p = period.of(t.done)
      if p.start < current.start then
        local affixes = config.get().affixes
        local key = (p.kind == "sprint" and affixes.sprint or affixes.week) .. p.key
        local to = fs.join(taskfile.dir(root), "archive", key, vim.fs.basename(t.path))
        table.insert(plan.tasks, { from = t.path, to = to, key = key })
      end
    end
  end
  -- Tasks with the same name in different folders under tasks/ would land on the same file, and
  -- one already in the archive would be replaced: either stops the archive before it starts.
  local by_to, order = {}, {}
  for _, t in ipairs(plan.tasks) do
    if not by_to[t.to] then
      by_to[t.to] = {}
      table.insert(order, t.to)
    end
    table.insert(by_to[t.to], t.from)
  end
  for _, to in ipairs(order) do
    local exists = fs.exists(to)
    if exists or #by_to[to] > 1 then
      table.insert(plan.conflicts, { to = to, from = by_to[to], exists = exists })
    end
  end
  return plan
end

---@param plan logpose.ArchivePlan
---@param path string
---@return string
local function relpath(plan, path)
  return require("logpose.link").relpath(plan.root, path)
end

--- Why the plan can't run: the moves that would overwrite a file. Nil when there are none.
---@param plan logpose.ArchivePlan
---@return string?
local function conflict_message(plan)
  if #plan.conflicts == 0 then
    return nil
  end
  local lines =
    { "logpose: nothing archived: these tasks would overwrite a file in the archive (rename them and try again):" }
  for _, c in ipairs(plan.conflicts) do
    local from = vim.tbl_map(function(path)
      return relpath(plan, path)
    end, c.from)
    local note = c.exists and " (already exists)" or ""
    table.insert(lines, ("  %s → %s%s"):format(table.concat(from, ", "), relpath(plan, c.to), note))
  end
  return table.concat(lines, "\n")
end

--- What moving the tasks does to the journal's links: links to the tasks follow them, and so do
--- the tasks' own (a markdown link is relative to the note it's in). A change per file.
---@param plan logpose.ArchivePlan
---@return { path: string, content: string }[]
local function link_changes(plan)
  local maintenance = require("logpose.maintenance")
  local markdown = require("logpose.markdown")
  local files = require("logpose.index").files(plan.root)
  local pairs_ = vim.tbl_map(function(t)
    return maintenance.link_pair(plan.root, t.from, t.to, files)
  end, plan.tasks)
  local changes = {}
  for _, file in ipairs(files) do
    local lines = fs.read_lines(file) or {}
    local code = markdown.code_rows(lines)
    local n = 0
    for i, l in ipairs(lines) do
      if not code[i] then
        local nl, m = maintenance.rewrite_links(l, pairs_, file)
        if m > 0 then
          lines[i], n = nl, n + m
        end
      end
    end
    if n > 0 then
      table.insert(changes, { path = file, content = table.concat(lines, "\n") })
    end
  end
  return changes
end

--- Move the tasks, and the links to them. Refuses up front, changing nothing, if a task or a note
--- linking to one has unsaved changes, or a task would overwrite a file in the archive. Returns
--- how many notes had their links to the tasks updated.
---@param plan logpose.ArchivePlan
---@return integer relinked
function M.execute(plan)
  local paths = vim.tbl_map(function(t)
    return t.from
  end, plan.tasks)
  local ok, err = fs.check_writable(paths)
  if not ok then
    error(err, 0)
  end
  local conflict = conflict_message(plan)
  if conflict then
    error(conflict, 0)
  end
  -- the links first: a rerun after a failed move finds those already pointing at the archive
  local relinks = link_changes(plan)
  ok, err = fs.check_writable(vim.tbl_map(function(c)
    return c.path
  end, relinks))
  if not ok then
    error(err, 0)
  end
  for _, c in ipairs(relinks) do
    local wrote, werr = fs.write_file(c.path, c.content)
    if not wrote then
      error(werr, 0)
    end
  end
  local moving = {}
  for _, p in ipairs(paths) do
    moving[p] = true
  end
  local relinked = #vim.tbl_filter(function(c)
    return not moving[c.path]
  end, relinks)
  local uv = vim.uv or vim.loop
  local moved = 0
  local done, move_err = pcall(function()
    for _, t in ipairs(plan.tasks) do
      fs.mkdir_p(vim.fs.dirname(t.to))
      -- checked again: a rename replaces a file that appeared since the plan was made
      if fs.exists(t.to) then
        error(("%s already exists"):format(relpath(plan, t.to)), 0)
      end
      local renamed, rename_err = uv.fs_rename(t.from, t.to)
      if not renamed then
        error(("cannot move %s: %s"):format(relpath(plan, t.from), rename_err), 0)
      end
      moved = moved + 1
      -- A buffer showing the task follows it to the archive.
      local buf = fs.find_buf(t.from)
      if buf then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! file " .. vim.fn.fnameescape(t.to))
          vim.cmd("silent! edit!")
        end)
      end
    end
  end)
  require("logpose.index").clear_cache()
  if not done then
    local why = tostring(move_err):gsub("^logpose:%s*", "")
    error(("logpose: archived %d of %d done tasks, then stopped: %s"):format(moved, #plan.tasks, why), 0)
  end
  return relinked
end

---@param plan logpose.ArchivePlan
---@param root string
---@return string[]
function M.describe(plan, root)
  local function rel(path)
    return require("logpose.link").relpath(root, path)
  end
  local lines =
    { ("Archive done tasks from before the current %s (%s)"):format(plan.current.kind, plan.current.label), "" }
  local keys, by_key = {}, {}
  for _, t in ipairs(plan.tasks) do
    if not by_key[t.key] then
      by_key[t.key] = {}
      table.insert(keys, t.key)
    end
    table.insert(by_key[t.key], vim.fs.basename(t.from))
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local dir = rel(fs.join(require("logpose.taskfile").dir(root), "archive", key))
    table.insert(lines, ("  → %s/: %s"):format(dir, table.concat(by_key[key], ", ")))
  end
  table.insert(lines, "")
  return lines
end

--- Show the plan in a scratch split. Returns the window.
---@param plan logpose.ArchivePlan
---@param root string
---@return integer win
function M.preview(plan, root)
  local lines = M.describe(plan, root)
  table.insert(lines, "q: close")
  return require("logpose.util.ui").scratch(
    lines,
    { name = "logpose://archive-preview", height = math.min(#lines, 20), locked = true }
  )
end

---@param plan logpose.ArchivePlan
---@param relinked integer notes whose links to the tasks were updated
local function report(plan, relinked)
  local n = #plan.tasks
  local links = relinked > 0 and ("; links to them updated in %d note%s"):format(relinked, relinked == 1 and "" or "s")
    or ""
  ui.notify(("logpose: archived %d done task%s%s"):format(n, n == 1 and "" or "s", links), vim.log.levels.INFO)
end

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    local plan = M.plan(root, date.today())
    if #plan.tasks == 0 then
      ui.notify(
        ("logpose: nothing to archive; every done task is from the current %s"):format(plan.current.kind),
        vim.log.levels.INFO
      )
      return
    end
    -- what can't be archived is said now, not after the preview asked about it
    local conflict = conflict_message(plan)
    if conflict then
      error(conflict, 0)
    end
    if opts.bang then
      report(plan, M.execute(plan))
      return
    end
    local win = M.preview(plan, root)
    vim.ui.select(
      { "Archive", "Cancel" },
      { prompt = "Archive these tasks?" },
      ui.safely(function(choice)
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if choice ~= "Archive" then
          ui.notify("logpose: archive cancelled", vim.log.levels.INFO)
          return
        end
        -- Re-plan: files may have changed while the preview was open.
        local fresh = M.plan(root, date.today())
        report(fresh, M.execute(fresh))
      end)
    )
  end))
end

return M

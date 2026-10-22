--- `:Logpose archive[!]`: move done tasks from past periods (weeks or sprints) into
--- `tasks/archive/<period>/`, out of the board. Archived tasks still show up in search and reports.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local period = require("logpose.period")
local ui = require("logpose.util.ui")

local M = {}

---@class logpose.ArchivePlan
---@field current logpose.Period  the current period (kept)
---@field tasks { from: string, to: string, key: string }[]  done task files to move

--- Work out what to move, entirely in memory. Nothing is written.
---@param root string
---@param today string
---@return logpose.ArchivePlan
function M.plan(root, today)
  local current = period.of(today)
  local plan = { current = current, tasks = {} }
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
  return plan
end

--- Move the tasks: refuses up front if any has unsaved changes.
---@param plan logpose.ArchivePlan
function M.execute(plan)
  local paths = vim.tbl_map(function(t)
    return t.from
  end, plan.tasks)
  local ok, err = fs.check_writable(paths)
  if not ok then
    error(err, 0)
  end
  for _, t in ipairs(plan.tasks) do
    fs.mkdir_p(vim.fs.dirname(t.to))
    if fs.exists(t.to) then
      error(("logpose: %s already exists (archive stopped)"):format(t.to), 0)
    end
    local moved, merr = (vim.uv or vim.loop).fs_rename(t.from, t.to)
    if not moved then
      error(("logpose: cannot move %s: %s"):format(t.from, merr), 0)
    end
    -- A buffer showing the task follows it to the archive.
    local buf = fs.find_buf(t.from)
    if buf then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent! file " .. vim.fn.fnameescape(t.to))
        vim.cmd("silent! edit!")
      end)
    end
  end
  require("logpose.index").clear_cache()
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
local function report(plan)
  local n = #plan.tasks
  ui.notify(("logpose: archived %d done task%s"):format(n, n == 1 and "" or "s"), vim.log.levels.INFO)
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
    if opts.bang then
      M.execute(plan)
      report(plan)
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
        M.execute(fresh)
        report(fresh)
      end)
    )
  end))
end

return M

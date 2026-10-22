--- Board undo/redo: every change made on the board is recorded as the files it changed, so
--- `u` and `<C-r>` put them back exactly (and refuse if a file changed in between).
local taskfile = require("logpose.taskfile")
local view = require("logpose.board.view")

local M = {}

--- Contents of every live task file (path -> text), read from disk.
---@param b logpose.Board
---@return table<string, string>
function M.snapshot(b)
  local fs = require("logpose.util.fs")
  local out = {}
  for _, t in ipairs(taskfile.list(b.root)) do
    out[t.path] = fs.read_file(t.path)
  end
  return out
end

--- Record what an action changed (compared with `before`) as one undo step.
---@param b logpose.Board
---@param label string
---@param before table<string, string>
function M.record(b, label, before)
  local after = M.snapshot(b)
  local changes = {}
  for path, content in pairs(before) do
    if after[path] ~= content then
      table.insert(changes, { path = path, before = content, after = after[path] })
    end
  end
  for path, content in pairs(after) do
    if before[path] == nil then
      table.insert(changes, { path = path, before = nil, after = content })
    end
  end
  if #changes > 0 then
    table.insert(b.undo, { label = label, changes = changes })
    b.redo = {}
  end
end

--- Put each changed file back to `side` ("before" for undo, "after" for redo), if nothing
--- else changed it in between.
---@param b logpose.Board
---@param step { label: string, changes: table[] }
---@param side "before"|"after"
---@return boolean ok, string? path a file to focus
local function apply(b, step, side)
  local fs = require("logpose.util.fs")
  local other = side == "before" and "after" or "before"
  for _, c in ipairs(step.changes) do
    if fs.read_file(c.path) ~= c[other] then
      return false
    end
    local buf = fs.find_buf(c.path)
    if buf and vim.bo[buf].modified then
      return false
    end
  end
  local focus
  for _, c in ipairs(step.changes) do
    if c[side] == nil then
      os.remove(c.path)
      local buf = fs.find_buf(c.path)
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    else
      local ok, err = fs.write_file(c.path, c[side], { raw = true })
      if not ok then
        error(err, 0)
      end
      focus = focus or c.path
    end
  end
  require("logpose.index").clear_cache()
  -- a task put back in or out of Done: the to-dos it was made from follow
  local done = require("logpose.config").get().board.done
  local function is_done(content)
    if not content then
      return nil
    end
    return require("logpose.index").frontmatter(vim.split(content, "\n", { plain = true })).status == done
  end
  for _, c in ipairs(step.changes) do
    local now, was = is_done(c[side]), is_done(c[other])
    if now ~= nil and was ~= nil and now ~= was then
      local ok, err = pcall(require("logpose.sync").set_todos, b.root, c.path, now)
      if not ok then
        require("logpose.util.ui").notify(require("logpose.util.ui").message(err), vim.log.levels.WARN)
      end
    end
  end
  return true, focus
end

--- `u`: take back the last change made on the board.
---@param b logpose.Board
function M.undo(b)
  local step = table.remove(b.undo)
  if not step then
    require("logpose.util.ui").notify("logpose: nothing to undo on the board", vim.log.levels.INFO)
    return
  end
  local ok, focus = apply(b, step, "before")
  if not ok then
    require("logpose.util.ui").notify(
      ("logpose: can't undo %s: the task changed since"):format(step.label),
      vim.log.levels.WARN
    )
    return
  end
  table.insert(b.redo, step)
  require("logpose.telemetry").record("board", { "undo" }, true)
  require("logpose.util.ui").notify(("logpose: undid %s"):format(step.label), vim.log.levels.INFO)
  view.refresh(b, focus)
end

--- `<C-r>`: redo what `u` took back.
---@param b logpose.Board
function M.redo(b)
  local step = table.remove(b.redo)
  if not step then
    require("logpose.util.ui").notify("logpose: nothing to redo on the board", vim.log.levels.INFO)
    return
  end
  local ok, focus = apply(b, step, "after")
  if not ok then
    require("logpose.util.ui").notify(
      ("logpose: can't redo %s: the task changed since"):format(step.label),
      vim.log.levels.WARN
    )
    return
  end
  table.insert(b.undo, step)
  require("logpose.telemetry").record("board", { "redo" }, true)
  require("logpose.util.ui").notify(("logpose: redid %s"):format(step.label), vim.log.levels.INFO)
  view.refresh(b, focus)
end

return M

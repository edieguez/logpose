--- :checkhealth logpose
local M = {}

function M.check()
  local h = vim.health
  local config = require("logpose.config")
  local fs = require("logpose.util.fs")

  h.start("logpose: environment")
  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. version)
  else
    h.error("Neovim " .. version .. " is too old; logpose needs 0.10+")
  end
  if config.options then
    h.ok("setup() has been called")
  else
    h.info("setup() not called; using defaults")
  end

  h.start("logpose: journal root")
  local root, source = config.resolve_root()
  if not root then
    h.error(source, {
      "Run :Logpose init to choose or create a journal directory",
      'Or set it in your config: require("logpose").setup({ root = "~/path/to/journal" })',
      "Or add one of these markers to the journal root: " .. table.concat(config.get().root_markers, ", "),
    })
    return
  end
  local how = ({
    config = "from setup({ root = ... })",
    buffer = "found by marker above the current buffer",
    cwd = "found by marker above the current directory",
    saved = "saved by :Logpose init",
  })[source] or source
  h.ok(("%s (%s)"):format(vim.fn.fnamemodify(root, ":~"), how))
  local uv = vim.uv or vim.loop
  if not uv.fs_access(root, "W") then
    h.error(
      ("%s can't be written to: logpose can't save notes or tasks there"):format(vim.fn.fnamemodify(root, ":~")),
      { "Check the folder's owner and permissions: ls -ld " .. vim.fn.shellescape(root) }
    )
  end
  if source == "buffer" or source == "cwd" then
    h.info("Run :Logpose init (or set `root`) so commands work from any buffer, e.g. a work repo.")
  end

  h.start("logpose: project")
  local project = require("logpose.project")
  h.info((project.describe(project.resolve(root)):gsub("^%l", string.upper)))

  h.start("logpose: archive periods")
  local popts = config.get().period
  local current = require("logpose.period").of(require("logpose.util.date").today())
  if popts.kind == "sprint" then
    h.ok(("By sprint (%d days): current is %s"):format(popts.sprint.length_days, current.label))
  else
    local day = require("logpose.util.date").weekday_name(current.start)
    h.ok(("By week, starting %s: current is %s"):format(day, current.label))
  end

  h.start("logpose: usage stats")
  if config.get().telemetry.enabled then
    h.ok("On (local only): " .. vim.fn.fnamemodify(require("logpose.telemetry").path(), ":~"))
  else
    h.info("Off (telemetry.enabled = false). They're local only; see :Logpose stats")
  end

  h.start("logpose: tasks")
  local taskfile = require("logpose.taskfile")
  local counts = {}
  for _, t in ipairs(taskfile.list(root)) do
    counts[t.status] = (counts[t.status] or 0) + 1
  end
  local parts = {}
  for _, c in ipairs(taskfile.columns()) do
    table.insert(parts, ("%s %d"):format(c.label, counts[c.key] or 0))
  end
  h.ok("Tasks: " .. table.concat(parts, " · "))

  h.start("logpose: journal size")
  local index = require("logpose.index")
  index.forget_build() -- measured, not reused from a moment ago
  local started = uv.hrtime()
  local items = index.build(root)
  local ms = math.floor((uv.hrtime() - started) / 1e6 + 0.5)
  local notes, tasks = 0, 0
  for _, it in ipairs(items) do
    if it.kind == "task" then
      tasks = tasks + 1
    elseif index.is_file(it) then
      notes = notes + 1
    end
  end
  local function count(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
  end
  h.info(("%s and %s, indexed in %d ms"):format(count(notes, "note"), count(tasks, "task"), ms))

  h.start("logpose: journal paths")
  local keys = vim.tbl_keys(config.get().dirs)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local path = config.path(key, root)
    local rel = config.get().dirs[key]
    if fs.exists(path) then
      h.ok(("%s: %s"):format(key, rel))
    else
      h.warn(("%s: %s does not exist yet (created on first use)"):format(key, rel))
    end
  end

  h.start("logpose: picker")
  local backend, warning = require("logpose.picker").detect(config.get().picker)
  if warning then
    h.warn(warning)
  end
  if backend == "select" then
    h.info("No picker plugin found; using vim.ui.select (snacks.nvim, fzf-lua or telescope recommended)")
  else
    h.ok("Using " .. backend)
  end
end

return M

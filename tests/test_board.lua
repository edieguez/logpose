local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local function task(name, fields, body)
  local lines = { "---", ('title: "%s"'):format(fields.title or name) }
  for _, k in ipairs({ "status", "project", "tags", "due", "blocked", "created", "started", "done", "order" }) do
    if fields[k] then
      table.insert(lines, k .. ": " .. fields[k])
    end
  end
  table.insert(lines, "---")
  table.insert(lines, "# " .. (fields.title or name))
  table.insert(lines, body or "")
  H.write(root .. "/tasks/" .. name .. ".md", table.concat(lines, "\n") .. "\n")
  return root .. "/tasks/" .. name .. ".md"
end

local function status(path)
  return child.lua_get(
    ("require('logpose.taskfile').parse(%q, vim.fn.readfile(%q), %q).status"):format(path, path, root)
  )
end

local function screen()
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.o.columns, child.o.lines = 160, 40
      setup()
      H.freeze(child, 2026, 10, 15) -- Thursday; the week started Monday 10-12
      task("fix-flaky", {
        title = "Fix flaky test",
        status = "todo",
        project = "acme",
        tags = "[perf]",
        due = "2026-10-14",
        created = "2026-10-10",
      })
      task("read-paper", { title = "Read paper", status = "backlog", project = "thesis", created = "2026-10-11" })
      task("queue", {
        title = "Queue design",
        status = "in-progress",
        project = "acme",
        blocked = "waiting on ana",
        created = "2026-10-09",
        started = "2026-10-12",
      })
      task("shipped", { title = "Ship it", status = "done", project = "acme", done = "2026-10-13" })
      task("old", { title = "Old work", status = "done", project = "acme", done = "2026-10-02" })
    end,
    post_once = child.stop,
  },
})

T["shows columns side by side with cards, counts and meta"] = function()
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, "Board · all projects")
  H.contains(s, " Backlog (1)")
  H.contains(s, "│ TODO (1)")
  H.contains(s, "│ In progress (1)")
  H.contains(s, "│ Follow-up (0)")
  H.contains(s, "│ Done (1)") -- "Old work" finished last week: not shown
  H.contains(s, "⛔ waiting on ana")
  H.contains(s, "acme · #perf · due 10-14")
  eq(s:find("Old work", 1, true), nil)
  eq(child.bo.filetype, "logpose-board")
  eq(child.bo.modifiable, false)
end

T["stacks the columns when the window is narrow"] = function()
  child.o.columns = 80
  child.cmd("Logpose board")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[3]:find("│", 1, true), nil)
  H.contains(screen(), " TODO (1)")
  -- focus and moves still work column by column
  child.type_keys("l")
  child.type_keys("L")
  eq(status(root .. "/tasks/fix-flaky.md"), "in-progress")
end

T["h/l/j/k move the focus; H/L, digits and x move the card"] = function()
  child.cmd("Logpose board")
  local flaky = root .. "/tasks/fix-flaky.md"
  child.type_keys("l") -- TODO column: Fix flaky test
  child.type_keys("L")
  eq(status(flaky), "in-progress")
  -- focus follows the card into In progress (sorted after Queue design: due first? no, order: due then created)
  child.type_keys("L")
  eq(status(flaky), "follow-up")
  child.type_keys("H")
  eq(status(flaky), "in-progress")
  child.type_keys("1")
  eq(status(flaky), "backlog")
  child.type_keys("x")
  eq(status(flaky), "done")
  H.contains(screen(), "Done (2)")
  local content = H.read(flaky)
  H.contains(content, "done: 2026-10-15")
  H.contains(content, "started: 2026-10-15")
  H.contains(content, "Follow-up → In progress")
end

T["b blocks with a reason and unblocks"] = function()
  child.cmd("Logpose board")
  child.lua([[vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('needs review') end]])
  child.type_keys("lb")
  eq(child.lua_get("_G.prompt"), "Blocked by: ")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "blocked: needs review")
  H.contains(screen(), "⛔ needs review")
  child.type_keys("b")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "blocked:\n")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "unblocked")
end

T["a adds a card to the focused column with the active project"] = function()
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(child.fn.getcwd()))
  child.cmd("Logpose board")
  child.lua([[vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('New idea') end]])
  child.type_keys("ll")
  child.type_keys("a")
  eq(child.lua_get("_G.prompt"), "New task in In progress: ")
  local content = H.read(root .. "/tasks/new-idea.md")
  H.contains(content, "status: in-progress")
  H.contains(content, "project: acme")
  H.contains(screen(), "New idea")
end

T["the active project scopes the board; p shows all"] = function()
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(child.fn.getcwd()))
  child.cmd("Logpose board")
  H.contains(screen(), "Board · acme")
  eq(screen():find("Read paper", 1, true), nil)
  child.type_keys("p")
  H.contains(screen(), "Board · all projects")
  H.contains(screen(), "Read paper")
end

T["filters from the command line and /"] = function()
  child.cmd("Logpose board #perf")
  H.contains(screen(), "Board · all projects · #perf")
  eq(screen():find("Read paper", 1, true), nil)
  H.contains(screen(), "Fix flaky test")
  child.lua([[vim.ui.input = function(opts, cb) _G.default = opts.default; cb('blocked') end]])
  child.type_keys("/")
  eq(child.lua_get("_G.default"), "#perf")
  H.contains(screen(), "Queue design")
  eq(screen():find("Fix flaky test", 1, true), nil)
end

T["J/K reorder cards within a column"] = function()
  task("a-first", { title = "Alpha", status = "todo", created = "2026-10-01" })
  child.cmd("Logpose board")
  child.type_keys("l") -- TODO: Fix flaky (due) then Alpha
  local s = screen()
  assert(s:find("Fix flaky test", 1, true) < s:find("Alpha", 1, true))
  child.type_keys("J")
  s = screen()
  assert(s:find("Alpha", 1, true) < s:find("Fix flaky test", 1, true))
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "order: 2")
  H.contains(H.read(root .. "/tasks/a-first.md"), "order: 1")
  -- moving to another column drops the order
  child.type_keys("L")
  eq(H.read(root .. "/tasks/fix-flaky.md"):find("order:", 1, true), nil)
end

T["the cursor selects a card; <CR> opens it and the board refreshes on return"] = function()
  child.cmd("Logpose board")
  -- put the cursor on the In progress card and let CursorMoved pick it up
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  for i, l in ipairs(lines) do
    if l:find("Queue design", 1, true) then
      row = i
    end
  end
  local col = lines[row]:find("Queue design", 1, true)
  child.api.nvim_win_set_cursor(0, { row, col })
  child.cmd("doautocmd CursorMoved")
  child.type_keys("<CR>")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/queue.md")
  child.lua(("require('logpose.taskfile').set_status(%q, 'follow-up')"):format(root .. "/tasks/queue.md"))
  child.cmd("buffer logpose://board")
  H.contains(screen(), "In progress (0)")
  H.contains(screen(), "Follow-up (1)")
end

T["q closes the board and returns to the previous buffer"] = function()
  child.cmd("edit " .. root .. "/tasks/read-paper.md")
  child.cmd("Logpose board")
  child.type_keys("q")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/read-paper.md")
  eq(child.fn.bufnr("logpose://board"), -1)
end

T["done_window can be a number of days"] = function()
  setup("{ board = { done_window = 30 } }")
  child.cmd("Logpose board")
  H.contains(screen(), "Done (2)")
  H.contains(screen(), "Old work")
end

T["triage opens the board on Backlog; ? shows help"] = function()
  child.cmd("Logpose triage")
  eq(child.bo.filetype, "logpose-board")
  child.type_keys("x")
  eq(status(root .. "/tasks/read-paper.md"), "done")
  child.type_keys("?")
  H.contains(child.notifications()[#child.notifications()].msg, "H / L  < >   move the card left / right")
end

T["custom columns"] = function()
  setup(
    [[{ board = { columns = { { key = 'todo', label = 'To do' }, { key = 'doing' }, { key = 'done', label = 'Done' } }, start = 'doing' }, tasks = { capture_status = 'todo', promote_status = 'todo' } }]]
  )
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, " To do (3)") -- statuses without a column show in the capture column
  H.contains(s, "│ doing (0)")
  child.type_keys("L")
  eq(status(root .. "/tasks/fix-flaky.md"), "doing")
end

T["standup lists board work; report and health count it"] = function()
  task("yesterday", { title = "Finished yesterday", status = "done", project = "acme", done = "2026-10-14" })
  child.cmd("Logpose standup")
  local s = screen()
  H.contains(s, "## Yesterday\n\n### acme\n\n- [x] Finished yesterday #acme")
  H.contains(s, "## Today\n\n### acme\n\n- [ ] Queue design #acme")
  H.contains(s, "## Blockers\n\n### acme\n\n- Queue design: waiting on ana #acme")

  local report = table.concat(
    child.lua_get(
      ("require('logpose.report').build(%q, require('logpose.period').of('2026-10-15'), {}, '2026-10-15', %q)"):format(
        root,
        root .. "/reports/x.md"
      )
    ),
    "\n"
  )
  H.contains(report, "- Ship it ([[tasks/shipped|Ship it]])  @acme")
  H.contains(
    report,
    "### Blocked tasks (1)\n\n- [In progress] Queue design: waiting on ana ([[tasks/queue|Queue design]])"
  )
  H.contains(report, "### In progress for more than 14 days (0)")

  child.cmd("checkhealth logpose")
  H.contains(screen(), "Task files: Backlog 1 · TODO 1 · In progress 1 · Follow-up 0 · Done 3")
end

T["archive moves done tasks from earlier periods"] = function()
  child.lua(
    [[vim.ui.select = function(items, opts, cb) _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false); cb('Archive') end]]
  )
  child.cmd("Logpose archive")
  H.contains(
    table.concat(child.lua_get("_G.preview"), "\n"),
    "Done tasks\n  → tasks/archive/week-2026-09-28/: old.md"
  )
  eq(H.read(root .. "/tasks/old.md"), nil)
  H.contains(H.read(root .. "/tasks/archive/week-2026-09-28/old.md"), "Old work")
  H.contains(child.notifications()[1].msg, "archived 1 done task")
  -- still counted in a report for that week
  local report = table.concat(
    child.lua_get(
      ("require('logpose.report').build(%q, require('logpose.period').of('2026-10-02'), {}, '2026-10-15', %q)"):format(
        root,
        root .. "/reports/x.md"
      )
    ),
    "\n"
  )
  H.contains(report, "- Old work")
end

return T

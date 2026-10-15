local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      setup()
      H.freeze(child, 2026, 10, 15, 9, 5)
    end,
    post_once = child.stop,
  },
})

local function create(spec)
  return child.lua_get(("require('logpose.taskfile').create(%q, %s)"):format(root, spec))
end

local function fm(path)
  return child.lua_get(("require('logpose.taskfile').parse(%q, vim.fn.readfile(%q), %q)"):format(path, path, root))
end

T["create writes frontmatter, body and a log"] = function()
  local path = create("{ title = 'Fix flaky test', project = 'acme', tags = { 'perf' }, due = '2026-10-20' }")
  eq(path, root .. "/tasks/fix-flaky-test.md")
  eq(
    H.read(path),
    table.concat({
      "---",
      'title: "Fix flaky test"',
      "status: backlog",
      "project: acme",
      "tags: [perf]",
      "due: 2026-10-20",
      "blocked:",
      "created: 2026-10-15",
      "started:",
      "done:",
      "---",
      "# Fix flaky test",
      "",
      "",
      "",
      "## Log",
      "- 2026-10-15 09:05: created in Backlog",
      "",
    }, "\n")
  )
  -- same title again: a new file
  eq(create("{ title = 'Fix flaky test' }"), root .. "/tasks/fix-flaky-test-2.md")
  eq(create("{ title = '¿Qué?' }"), root .. "/tasks/que.md")
end

T["create puts body lines where the cursor goes and validates the column"] = function()
  local path = create("{ title = 'Promoted', status = 'todo', body = { 'From: [[x]]' } }")
  local content = H.read(path)
  H.contains(content, "# Promoted\n\nFrom: [[x]]\n\n")
  H.contains(content, "status: todo")
  MiniTest.expect.error(function()
    create("{ title = 'Nope', status = 'nope' }")
  end, "unknown board column")
end

T["from_text splits tags and due dates out of the title"] = function()
  eq(
    child.lua_get("{ require('logpose.taskfile').from_text('fix CI #perf @ana due:2026-10-20 #acme') }"),
    { "fix CI @ana", { "perf", "acme" }, "2026-10-20" }
  )
  eq(child.lua_get("{ require('logpose.taskfile').from_text('#only') }"), { "#only", { "only" } })
end

T["set_status keeps started, done and the log in step"] = function()
  local path = create("{ title = 'Move me' }")
  local set = function(status)
    return child.lua_get(("require('logpose.taskfile').set_status(%q, %q)"):format(path, status))
  end
  eq(set("in-progress"), true)
  local t = fm(path)
  eq({ t.status, t.started, t.done == nil }, { "in-progress", "2026-10-15", true })
  H.freeze(child, 2026, 10, 16, 17, 0)
  child.lua(("require('logpose.taskfile').set_blocked(%q, 'waiting on ana')"):format(path))
  eq(fm(path).blocked, "waiting on ana")
  eq(set("done"), true)
  t = fm(path)
  eq({ t.status, t.started, t.done, t.blocked == nil }, { "done", "2026-10-15", "2026-10-16", true })
  eq(set("done"), false) -- already there
  eq(set("todo"), true)
  t = fm(path)
  eq({ t.status, t.started, t.done == nil }, { "todo", "2026-10-15", true }) -- started stays
  H.contains(
    H.read(path),
    table.concat({
      "## Log",
      "- 2026-10-15 09:05: created in Backlog",
      "- 2026-10-15 09:05: Backlog → In progress",
      "- 2026-10-16 17:00: blocked: waiting on ana",
      "- 2026-10-16 17:00: In progress → Done",
      "- 2026-10-16 17:00: Done → TODO",
    }, "\n")
  )
end

T["set_status edits an unsaved buffer instead of the file"] = function()
  local path = create("{ title = 'Open' }")
  child.cmd("edit " .. path)
  child.api.nvim_buf_set_lines(0, 13, 13, false, { "my unsaved context" })
  child.lua(("require('logpose.taskfile').set_status(%q, 'todo')"):format(path))
  H.contains(H.read(path), "status: backlog") -- disk untouched
  local buf = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(buf, "status: todo")
  H.contains(buf, "my unsaved context")
end

T["set_field adds missing keys in order and leaves absent keys alone when clearing"] = function()
  local lines = child.lua_get(
    [[require('logpose.taskfile').set_field({ '---', 'title: "x"', 'created: 2026-10-01', '---' }, 'status', 'todo')]]
  )
  eq(lines, { "---", 'title: "x"', "status: todo", "created: 2026-10-01", "---" })
  lines = child.lua_get([[require('logpose.taskfile').set_field({ '---', 'title: "x"', '---' }, 'order', nil)]])
  eq(lines, { "---", 'title: "x"', "---" })
end

T["list skips archived tasks unless asked"] = function()
  create("{ title = 'Live' }")
  H.write(root .. "/tasks/archive/week-2026-10-05/old.md", "---\ntitle: Old\nstatus: done\ndone: 2026-10-06\n---\n")
  eq(child.lua_get(("#require('logpose.taskfile').list(%q)"):format(root)), 1)
  local all = child.lua_get(("require('logpose.taskfile').list(%q, { archived = true })"):format(root))
  eq(#all, 2)
  eq(all[1].archived, true)
end

T["index and find see task files with their board fields"] = function()
  local path = create("{ title = 'Fix flaky test', project = 'acme', tags = { 'perf' } }")
  child.lua(("require('logpose.taskfile').set_status(%q, 'in-progress')"):format(path))
  child.lua(("require('logpose.taskfile').set_blocked(%q, 'ci down')"):format(path))
  create("{ title = 'Other', status = 'done' }")
  local q = function(args)
    return child.lua_get(
      ([[vim.tbl_map(function(it) return it.text end,
      vim.tbl_filter(function(it) return it.kind == 'note' and it.note_type == 'task' end,
        require('logpose.query').filter(require('logpose.index').build(%q), require('logpose.query').parse(%s))))]]):format(
        root,
        args
      )
    )
  end
  eq(q("{ 'status:in-progress' }"), { "Fix flaky test" })
  eq(q("{ 'blocked' }"), { "Fix flaky test" })
  eq(q("{ 'open' }"), { "Fix flaky test" })
  eq(q("{ 'done' }"), { "Other" })
  eq(q("{ '#perf', 'project:acme' }"), { "Fix flaky test" })
  setup("{ picker = 'select' }")
  child.lua([[vim.ui.select = function(items, opts, cb) _G.labels = vim.tbl_map(opts.format_item, items) end]])
  child.cmd("Logpose find tasks")
  eq(child.lua_get("_G.labels"), { "[In progress] Fix flaky test  ⛔  @acme", "[Done] Other" })
end

T["capture creates a Backlog task; capture! opens it"] = function()
  setup("{ projects = { paths = { [vim.fn.getcwd()] = 'acme' } } }")
  child.cmd("Logpose capture fix flaky test #perf #acme due:2026-10-20")
  local path = root .. "/tasks/fix-flaky-test.md"
  local t = fm(path)
  eq({ t.title, t.status, t.project, t.tags, t.due }, { "fix flaky test", "backlog", "acme", { "perf" }, "2026-10-20" })
  H.contains(child.notifications()[1].msg, "captured to Backlog: tasks/fix-flaky-test.md")
  eq(child.api.nvim_buf_get_name(0), "") -- not opened
  child.cmd("Logpose capture! write the retro")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/write-the-retro.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 14)
  eq(H.read(root .. "/INBOX.md"), nil)
end

T["done moves a task file to Done; checkboxes elsewhere are just checked"] = function()
  local path = create("{ title = 'Finish me' }")
  child.cmd("edit " .. path)
  child.cmd("Logpose done")
  eq(fm(path).status, "done")
  H.contains(child.notifications()[1].msg, "moved to Done")
  child.cmd("Logpose done")
  H.contains(child.notifications()[2].msg, "already Done")

  H.write(root .. "/daily/daily-2026-10-15.md", "# daily\n## Today\n- [ ] small thing\n")
  child.cmd("edit " .. root .. "/daily/daily-2026-10-15.md")
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Logpose done")
  H.contains(H.read(root .. "/daily/daily-2026-10-15.md"), "- [x] small thing")
  eq(H.read(root .. "/DONE.md"), nil) -- no DONE.md log with task files
end

T["promote turns a checkbox into a linked task file"] = function()
  H.write(
    root .. "/meetings/acme/2026-10-15 - retro.md",
    '---\ntype: retro\nproject: acme\ntitle: "Retro"\n---\n# Retro\n## Action items\n- [ ] fix CI #perf @ana due:2026-10-20\n'
  )
  child.cmd("edit " .. root .. "/meetings/acme/2026-10-15 - retro.md")
  child.api.nvim_win_set_cursor(0, { 8, 0 })
  child.cmd("Logpose promote")
  local path = root .. "/tasks/fix-ci-ana.md"
  local t = fm(path)
  eq({ t.title, t.status, t.project, t.tags, t.due }, { "fix CI @ana", "todo", "acme", { "perf" }, "2026-10-20" })
  H.contains(H.read(path), "From: [[meetings/acme/2026-10-15 - retro|Retro]]")
  eq(child.api.nvim_buf_get_lines(0, 7, 8, false)[1], "- [ ] [[tasks/fix-ci-ana|fix CI @ana]]")
  eq(child.bo.modified, false) -- saved
  child.api.nvim_win_set_cursor(0, { 6, 0 })
  child.cmd("Logpose promote")
  H.contains(child.notifications()[#child.notifications()].msg, "no checkbox on this line")
end

T["migrate turns open INBOX items into task files"] = function()
  H.write(root .. "/meetings/acme/2026-10-01 - retro.md", "---\ntype: retro\nproject: acme\n---\n# Retro\n")
  H.write(
    root .. "/INBOX.md",
    table.concat({
      "# INBOX",
      "",
      "## 2026-10-13",
      "- [ ] fix flaky test #perf #acme due:2026-10-20",
      "  - seen on Mondays",
      "  - logs in CI",
      "- [x] already done",
      "- [ ] read paper",
      "",
      "## Someday",
      "- [ ] learn rust",
      "",
    }, "\n")
  )
  child.cmd("Logpose migrate!")
  local a = fm(root .. "/tasks/fix-flaky-test.md")
  eq({ a.status, a.project, a.tags, a.due, a.created }, { "backlog", "acme", { "perf" }, "2026-10-20", "2026-10-13" })
  H.contains(H.read(root .. "/tasks/fix-flaky-test.md"), "# fix flaky test\n\n- seen on Mondays\n- logs in CI\n")
  eq(fm(root .. "/tasks/read-paper.md").created, "2026-10-13")
  eq(fm(root .. "/tasks/learn-rust.md").tags, { "someday" })
  eq(H.read(root .. "/INBOX.md"), "# INBOX\n\n## 2026-10-13\n- [x] already done\n\n## Someday\n")
  H.contains(child.notifications()[1].msg, "migrated 3 tasks to Backlog")
  child.cmd("Logpose migrate")
  H.contains(child.notifications()[2].msg, "no open INBOX tasks")
end

T["migrate previews and can be cancelled"] = function()
  H.write(root .. "/INBOX.md", "# INBOX\n\n## 2026-10-13\n- [ ] one #ux\n")
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    cb('Cancel')
  end]])
  child.cmd("Logpose migrate")
  eq(child.lua_get("_G.preview"), { "Migrate 1 INBOX task to Backlog:", "", "  one  (#ux)" })
  eq(H.read(root .. "/INBOX.md"), "# INBOX\n\n## 2026-10-13\n- [ ] one #ux\n")
  eq(child.lua_get(("vim.fn.isdirectory(%q)"):format(root .. "/tasks")), 0)
end

T["config rejects bad columns"] = function()
  local err = function(opts)
    return child.lua_get(("select(2, pcall(require('logpose').setup, %s))"):format(opts))
  end
  H.contains(err("{ board = { columns = { { key = 'a' } } } }"), "at least two columns")
  H.contains(err("{ board = { columns = { { key = 'a' }, { key = 'a' } } } }"), 'duplicate board column "a"')
  H.contains(err("{ board = { columns = { { key = 'a' }, { key = 'b' } } } }"), "is not a board column")
  H.contains(err("{ tasks = { mode = 'kanban' } }"), "`tasks.mode`")
end

return T

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
      "created: 2026-10-15T09:05",
      "modified: 2026-10-15T09:05",
      "started:",
      "done:",
      "---",
      "## Context",
      "",
      "## Log",
      "",
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
  H.contains(content, "---\n## Context\n\nFrom: [[x]]\n\n## Log\n")
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

T["from_text takes a +project and relative due dates"] = function()
  local function ft(s)
    return child.lua_get(("{ require('logpose.taskfile').from_text(%q) }"):format(s))
  end
  eq(ft("Write chapter +thesis"), { "Write chapter", {}, vim.NIL, "thesis" })
  eq(ft("Plan project:Master-Thesis due:fri"), { "Plan", {}, "2026-10-16", "master-thesis" }) -- a Thursday
  eq(ft("Bump deps due:+3d +acme"), { "Bump deps", {}, "2026-10-18", "acme" })
  eq(ft("Tidy up +none"), { "Tidy up", {}, vim.NIL, false })
  -- not projects: C++, +1, a word with + inside; not dates: due:someday
  eq(ft("Fix C++ build +1 a+b"), { "Fix C++ build +1 a+b", {} })
  eq(ft("Decide due:someday"), { "Decide due:someday", {} })
end

T["set_status on a CRLF file keeps one frontmatter block"] = function()
  local path = root .. "/tasks/crlf.md"
  H.write(path, '---\r\ntitle: "X"\r\nstatus: todo\r\n---\r\n# X\r\n')
  eq(child.lua_get(("require('logpose.taskfile').set_status(%q, 'in-progress')"):format(path)), true)
  local content = H.read(path)
  eq(select(2, content:gsub("\n%-%-%-\n", "")), 1)
  H.contains(content, 'title: "X"\nstatus: in-progress\n')
  H.contains(content, "TODO → In progress")
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
      "",
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

T["list reads tasks with unsaved changes from their buffer"] = function()
  local path = create("{ title = 'Open' }")
  create("{ title = 'Other' }")
  child.cmd("edit " .. path)
  child.cmd("%s/^status: backlog$/status: todo/")
  local statuses = child.lua_get(
    ("vim.tbl_map(function(t) return t.status end, require('logpose.taskfile').list(%q))"):format(root)
  )
  eq(statuses, { "todo", "backlog" })
end

T["set_field adds missing keys in order and leaves absent keys alone when clearing"] = function()
  local lines = child.lua_get(
    [[require('logpose.taskfile').set_field({ '---', 'title: "x"', 'created: 2026-10-01', '---' }, 'status', 'todo')]]
  )
  eq(lines, { "---", 'title: "x"', "status: todo", "created: 2026-10-01", "---" })
  lines = child.lua_get([[require('logpose.taskfile').set_field({ '---', 'title: "x"', '---' }, 'order', nil)]])
  eq(lines, { "---", 'title: "x"', "---" })
end

T["path_for skips names used by archived tasks"] = function()
  H.write(root .. "/tasks/archive/week-2026-10-05/fix-login.md", "# old\n")
  H.write(root .. "/tasks/archive/week-2026-10-12/fix-login-2.md", "# older\n")
  eq(
    child.lua_get(("require('logpose.taskfile').path_for(%q, 'Fix login')"):format(root)),
    root .. "/tasks/fix-login-3.md"
  )
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
      vim.tbl_filter(function(it) return it.kind == 'task' end,
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

T["+name in a capture picks the project; :Logpose edit last fixes a wrong one"] = function()
  setup("{ projects = { paths = { [vim.fn.getcwd()] = 'acme' } } }")
  child.cmd("Logpose capture Write chapter 3 +thesis due:tomorrow")
  local t = fm(root .. "/tasks/write-chapter-3.md")
  eq({ t.title, t.project, t.due }, { "Write chapter 3", "thesis", "2026-10-16" })
  H.contains(child.notifications()[1].msg, "→ thesis · Backlog")
  child.cmd("Logpose capture Water the plants +none")
  eq(fm(root .. "/tasks/water-the-plants.md").project, nil)
  H.contains(child.notifications()[2].msg, "→ no project")
  -- no text: the new-task form, starting from the detected project
  child.cmd("Logpose capture")
  eq(child.bo.filetype, "logpose-edit")
  eq(vim.list_slice(child.api.nvim_buf_get_lines(0, 0, -1, false), 1, 3), { "", "backlog", "acme" })
  child.type_keys("Ship it", "<Esc>")
  child.cmd("write")
  H.contains(child.notifications()[#child.notifications()].msg, "created “Ship it” → acme · Backlog")
  child.type_keys("q")
  -- not in a journal note: :Logpose edit opens the last capture
  child.cmd("Logpose edit")
  eq(child.bo.filetype, "logpose-edit")
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "Ship it")
  child.type_keys("q")
  child.cmd("Logpose edit last")
  eq(child.bo.filetype, "logpose-edit")
end

T["capture completes +projects, #tags and due:"] = function()
  H.write(root .. "/projects/thesis.md", '---\ntitle: "Thesis"\nproject: thesis\n---\n')
  H.write(root .. "/tasks/x.md", "---\ntitle: x\nstatus: todo\ntags: [perf]\n---\n")
  local function complete(line)
    return child.fn.getcompletion(line, "cmdline")
  end
  eq(complete("Logpose capture Fix +th"), { "+thesis" })
  eq(complete("Logpose capture Fix #pe"), { "#perf" })
  eq(complete("Logpose capture Fix due:to"), { "due:today", "due:tomorrow" })
end

T["capture creates a Backlog task; capture! opens it"] = function()
  setup("{ projects = { paths = { [vim.fn.getcwd()] = 'acme' } } }")
  child.cmd("Logpose capture fix flaky test #perf #acme due:2026-10-20")
  local path = root .. "/tasks/fix-flaky-test.md"
  local t = fm(path)
  eq({ t.title, t.status, t.project, t.tags, t.due }, { "fix flaky test", "backlog", "acme", { "perf" }, "2026-10-20" })
  -- says where it went and why, and how to fix a wrong guess
  H.contains(
    child.notifications()[1].msg,
    "captured “fix flaky test” → acme (projects.paths) · Backlog · :Logpose edit last to change"
  )
  eq(child.api.nvim_buf_get_name(0), "") -- not opened
  child.cmd("Logpose capture! write the retro")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/write-the-retro.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 14) -- the blank line under ## Context
end

T["done moves the task you're in to Done"] = function()
  local path = create("{ title = 'Finish me' }")
  child.cmd("edit " .. path)
  child.cmd("Logpose done")
  eq(fm(path).status, "done")
  H.contains(child.notifications()[1].msg, "moved to Done")
  child.cmd("Logpose done")
  H.contains(child.notifications()[2].msg, "already Done")
end

T["promote turns a to-do into a linked task"] = function()
  H.write(
    root .. "/meetings/acme/2026-10-15 - retro.md",
    '---\ntype: retro\nproject: acme\ntitle: "Retro"\n---\n# Retro\n## Action items\n- [ ] fix CI #perf @ana due:2026-10-20\n'
  )
  child.cmd("edit " .. root .. "/meetings/acme/2026-10-15 - retro.md")
  child.api.nvim_win_set_cursor(0, { 8, 0 })
  child.cmd("Logpose promote")
  local path = root .. "/tasks/fix-ci-ana.md"
  local t = fm(path)
  eq({ t.title, t.status, t.project, t.tags, t.due }, { "fix CI @ana", "backlog", "acme", { "perf" }, "2026-10-20" })
  H.contains(H.read(path), "From: [[meetings/acme/2026-10-15 - retro|Retro]]")
  -- both ways: the action item keeps its owner and due date and links to the task
  eq(
    child.api.nvim_buf_get_lines(0, 7, 9, false),
    { "- [ ] fix CI #perf @ana due:2026-10-20", "  → [[tasks/fix-ci-ana|task]]" }
  )
  child.cmd("Logpose actions")
  H.contains(child.fn.getqflist()[1].text, "fix CI #perf @ana due:2026-10-20")
  child.cmd("cclose")
  eq(child.bo.modified, false) -- saved
  child.api.nvim_win_set_cursor(0, { 6, 0 })
  child.cmd("Logpose promote")
  H.contains(child.notifications()[#child.notifications()].msg, "no to-do on this line")
end

T["config rejects bad columns"] = function()
  local err = function(opts)
    return child.lua_get(("select(2, pcall(require('logpose').setup, %s))"):format(opts))
  end
  H.contains(err("{ board = { columns = { { key = 'a' } } } }"), "at least two columns")
  H.contains(err("{ board = { columns = { { key = 'a' }, { key = 'a' } } } }"), 'duplicate board column "a"')
  H.contains(err("{ board = { columns = { { key = 'a' }, { key = 'b' } } } }"), "is not a board column")
end

return T

local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
      child.lua([[
        vim.ui.input = function(_, cb) cb(table.remove(_G.answers or {}, 1)) end
        _G.pick = function(...)
          local wants = { ... }
          vim.ui.select = function(items, o, cb)
            _G.labels = vim.tbl_map(o.format_item or function(x) return x.display or x end, items)
            _G.previews = vim.tbl_map(function(x) return type(x) == "table" and x.preview or nil end, items)
            for _, want in ipairs(wants) do
              for _, it in ipairs(items) do
                local v = type(it) == "table" and (it.value or it.name or it.display or it.label) or it
                if v == want or (type(it) == "table" and it.display and it.display:find(want, 1, true)) then
                  return cb(it)
                end
              end
            end
            cb(nil)
          end
        end
        _G.pick("Apply")
      ]])
    end,
    post_once = child.stop,
  },
})

local function task(name, project, status, extra)
  H.write(
    root .. "/tasks/" .. name .. ".md",
    ("---\ntitle: %q\nstatus: %s\n%s%s---\n## Context\n\n## Log\n"):format(
      name,
      status or "in-progress",
      project and ("project: " .. project .. "\n") or "",
      extra or ""
    )
  )
end

local function page(name, extra)
  H.write(
    root .. "/projects/" .. name .. ".md",
    ("---\ntitle: %q\ntype: project\nproject: %s\n%s---\n## Overview\n"):format(name, name, extra or "")
  )
end

local function lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function text()
  return table.concat(lines(), "\n")
end

--- Set a file's modification time to `days` days before the frozen today.
local function age(path, days)
  local t = os.time({ year = 2026, month = 10, day = 15, hour = 10 }) - days * 86400
  vim.uv.fs_utime(path, t, t)
end

--- Board cards as titles.
local function cards()
  return child.lua_get([[(function()
    local b = require('logpose.board').boards[vim.api.nvim_get_current_buf()]
    local out = {}
    for _, c in ipairs(b.columns) do
      for _, it in ipairs(c.cards) do table.insert(out, it.title) end
    end
    table.sort(out)
    return out
  end)()]])
end

local function project_of(name)
  return H.read(root .. "/tasks/" .. name .. ".md"):match("\nproject:[ \t]*([^\n]*)")
end

local function on(pattern)
  child.fn.search(pattern)
end

T["switching"] = MiniTest.new_set()

T["switching"][":Logpose project completes projects that only exist in task files and pages"] = function()
  task("a", "logpose")
  task("b", "hiraishin")
  page("thesis")
  page("old", "archived: true\n")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "hiraishin", "logpose", "thesis", "none", "auto" })
  -- archived projects stay searchable
  eq(
    child.lua_get(("require('logpose.search').projects(%q, require('logpose.index').build(%q))"):format(root, root)),
    { "hiraishin", "logpose", "old", "thesis" }
  )
end

T["switching"]["an open board follows the project you switch to"] = function()
  task("a", "logpose")
  task("b", "logpose")
  task("c", "hiraishin")
  child.cmd("Logpose project hiraishin")
  child.cmd("Logpose board")
  eq(cards(), { "c" })
  child.cmd("Logpose project logpose")
  eq(cards(), { "a", "b" })
  H.contains(child.lua_get("vim.wo.winbar"), "logpose")
  child.cmd("Logpose project none") -- inside the journal: no project, so all of them
  eq(cards(), { "a", "b", "c" })
end

T["switching"]["the all-projects board leaves archived projects out"] = function()
  task("a", "logpose")
  task("c", "hiraishin")
  page("hiraishin", "archived: true\n")
  child.cmd("Logpose board")
  eq(cards(), { "a" })
  child.lua(("require('logpose.board').open_board(%q, { project = 'hiraishin' })"):format(root))
  eq(cards(), { "c" })
end

T["switching"]["a project page's paths make its repo detect as that project"] = function()
  local repo = H.tmpdir()
  vim.fn.mkdir(repo .. "/.git", "p")
  vim.fn.mkdir(repo .. "/src", "p")
  H.write(repo .. "/src/main.go", "package main\n")
  page("acme", ("paths: [%s]\n"):format(repo))
  child.cmd("edit " .. repo .. "/src/main.go")
  eq(child.lua_get(("{ require('logpose.project').resolve(%q) }"):format(root)), { "acme", "page" })
end

T["switching from the projects screen"] = MiniTest.new_set()

T["switching from the projects screen"][":Logpose project without a name opens it; <CR> switches and opens the board"] = function()
  task("a", "acme")
  task("b", "thesis")
  child.cmd("edit " .. root .. "/tasks/a.md")
  child.cmd("Logpose project")
  eq(child.bo.filetype, "logpose-projects")
  on("thesis")
  child.type_keys("<CR>")
  eq(child.bo.filetype, "logpose-board")
  eq(cards(), { "b" })
  -- by name, straight there
  child.cmd("enew")
  child.cmd("Logpose project acme")
  eq(cards(), { "a" })
  -- c goes back to detecting the project
  child.cmd("Logpose project")
  child.type_keys("c")
  eq(child.lua_get("require('logpose.state').get('project')"), vim.NIL)
end

T["switching from the projects screen"]["projects.open_board = false keeps you where you are"] = function()
  task("a", "acme")
  child.lua(
    ("require('logpose').setup({ root = %q, picker = 'select', projects = { open_board = false } })"):format(root)
  )
  child.cmd("edit " .. root .. "/tasks/a.md")
  child.cmd("Logpose project acme")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/a.md")
  child.cmd("Logpose projects")
  on("acme")
  child.type_keys("<CR>")
  eq(child.bo.filetype, "logpose-projects")
  H.contains(lines()[3], "Active: acme (pinned)")
end

T["switching from the projects screen"]["P on the board opens it, and the board follows the switch"] = function()
  task("a", "acme")
  task("b", "thesis")
  child.cmd("Logpose project acme")
  child.cmd("Logpose board")
  eq(cards(), { "a" })
  local board = child.api.nvim_get_current_buf()
  child.type_keys("P")
  eq(child.bo.filetype, "logpose-projects")
  on("thesis")
  child.type_keys("<CR>")
  eq(child.api.nvim_get_current_buf(), board) -- the same board, not a new one
  eq(cards(), { "b" })
end

T["moving tasks"] = MiniTest.new_set()

T["moving tasks"]["m on the board moves the card to another project, and u undoes it"] = function()
  task("a", "acme", "todo")
  task("b", "thesis", "todo")
  child.cmd("Logpose board")
  child.lua([[(function()
    local b = require('logpose.board').boards[vim.api.nvim_get_current_buf()]
    for ci, c in ipairs(b.columns) do
      for ri, it in ipairs(c.cards) do
        if it.title == 'a' then b.focus = { col = ci, row = ri } end
      end
    end
  end)()]])
  child.lua("_G.pick('thesis')")
  child.type_keys("m")
  eq(project_of("a"), "thesis")
  H.contains(H.read(root .. "/tasks/a.md"), "project: acme → thesis")
  child.type_keys("u")
  eq(project_of("a"), "acme")
end

T["manager"] = MiniTest.new_set()

T["manager"]["shows what needs attention, most recently active first, with stale ones faded"] = function()
  task("a", "acme", "in-progress", "due: 2026-10-12\n")
  task("b", "acme", "todo", "blocked: waiting\ndue: 2026-10-30\n")
  task("c", "acme", "done")
  task("d", "acme", "todo", "due: 2026-10-17\n")
  task("e", "thesis", "todo")
  task("f", "legacy", "todo")
  page("Empty")
  for _, f in ipairs({ "a", "b", "c", "d" }) do
    age(root .. "/tasks/" .. f .. ".md", 1)
  end
  age(root .. "/tasks/e.md", 3)
  age(root .. "/tasks/f.md", 40)
  age(root .. "/projects/Empty.md", 5)
  child.cmd("Logpose project acme")
  child.cmd("Logpose projects")
  local l = lines()
  eq(l[1], "# Projects")
  H.contains(l[3], "Active: acme (pinned)")
  local rows = {}
  for _, line in ipairs(l) do
    local name = line:match("^  .-▸ (%S+)")
    if name then
      table.insert(rows, name)
      rows[name] = line
    end
  end
  eq({ rows[1], rows[2], rows[3], rows[4] }, { "acme", "thesis", "Empty", "legacy" })
  H.contains(rows.acme, "3 open (1 in progress) · 1 overdue · 1 due soon · 1 blocked")
  H.contains(rows.acme, "yesterday")
  H.contains(rows.thesis, "3d ago")
  H.contains(rows.Empty, "project page only")
  H.contains(rows.legacy, "5w ago")
  -- the stale one is drawn in Comment
  local row = vim.fn.index(l, rows.legacy)
  local marks = child.api.nvim_buf_get_extmarks(0, -1, { row, 0 }, { row, -1 }, { details = true })
  local groups = vim.tbl_map(function(m)
    return m[4].hl_group
  end, marks)
  eq(vim.tbl_contains(groups, "Identifier"), false)
end

T["manager"]["<Tab> expands a project in place; <CR> on a detail line opens it"] = function()
  task("fix-test", "acme", "in-progress")
  task("rate-limits", "acme", "todo", "blocked: waiting on ana\n")
  page("acme", "description: Payments API\npaths: [~/work/acme-api]\n")
  child.cmd("Logpose projects")
  on("acme")
  child.type_keys("<Tab>")
  local t = text()
  H.contains(t, "▾ acme")
  H.contains(t, "        Payments API")
  H.contains(t, "        repo: ~/work/acme-api")
  H.contains(t, "          • rate-limits  waiting on ana")
  child.type_keys("<Tab>")
  eq(text():find("Payments API", 1, true), nil)
  child.type_keys("<Tab>")
  on("rate-limits")
  child.type_keys("<CR>")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/rate-limits.md")
end

T["manager"]["<CR> switches and c goes back to auto-detect"] = function()
  task("a", "acme")
  task("b", "thesis")
  child.cmd("Logpose projects")
  on("thesis")
  child.type_keys("<CR>")
  eq(child.lua_get("require('logpose.project').current()"), "thesis")
  eq(child.bo.filetype, "logpose-board") -- switching opens the board
  eq(cards(), { "b" })
  child.cmd("Logpose projects")
  H.contains(lines()[3], "Active: thesis (pinned)")
  child.type_keys("c")
  eq(child.lua_get("require('logpose.state').get('project')"), vim.NIL)
end

T["manager"]["a adds a project with a display name and its repo folder"] = function()
  local repo = H.tmpdir()
  child.cmd("Logpose projects")
  H.contains(text(), "No projects yet")
  child.lua(("_G.answers = { 'Thesis Work', %q }"):format(repo))
  child.type_keys("a")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "projects")
  local t = H.read(root .. "/projects/thesis-work.md")
  H.contains(t, 'title: "Thesis Work"')
  H.contains(t, "project: thesis-work")
  H.contains(t, "paths: [" .. vim.fn.fnamemodify(repo, ":~"))
  H.contains(child.api.nvim_get_current_line(), "Thesis Work")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "thesis-work", "none", "auto" })
end

T["manager"]["p links another repo folder"] = function()
  local repo = H.tmpdir()
  page("acme", "paths: [~/one]\n")
  child.cmd("Logpose projects")
  on("acme")
  child.lua(("_G.answers = { %q }"):format(repo))
  child.type_keys("p")
  H.contains(H.read(root .. "/projects/acme.md"), "paths: [~/one, " .. vim.fn.fnamemodify(repo, ":~"))
end

T["manager"]["D archives a project and U restores it"] = function()
  task("a", "acme")
  task("b", "thesis")
  page("acme")
  child.cmd("Logpose project acme")
  child.cmd("Logpose projects")
  child.lua("_G.pick('Archive')")
  on("acme")
  child.type_keys("D")
  H.contains(H.read(root .. "/projects/acme.md"), "archived: true")
  eq(project_of("a"), "acme")
  eq(child.lua_get("require('logpose.state').get('project')"), vim.NIL)
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "thesis", "none", "auto" })
  H.contains(text(), "## Archived (1)  A shows them")
  child.type_keys("A")
  on("▸ acme")
  child.type_keys("U")
  eq(H.read(root .. "/projects/acme.md"):match("archived") == nil, true)
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "acme", "thesis", "none", "auto" })
end

T["manager"]["R renames everywhere"] = function()
  task("a", "logpose")
  page("logpose")
  child.cmd("Logpose project logpose")
  child.cmd("Logpose projects")
  on("logpose")
  child.lua("_G.answers = { 'log-pose' }")
  child.type_keys("R")
  eq(project_of("a"), "log-pose")
  eq(vim.fn.filereadable(root .. "/projects/log-pose.md"), 1)
  eq(child.lua_get("require('logpose.state').get('project')"), "log-pose")
  H.contains(text(), "● ▸ logpose") -- the page keeps its title
end

T["manager"]["b opens the board for that project and n its page"] = function()
  task("a", "acme")
  task("b", "thesis")
  child.cmd("Logpose projects")
  on("thesis")
  child.type_keys("b")
  eq(child.api.nvim_buf_get_name(0):match("logpose://board") ~= nil, true)
  eq(cards(), { "b" })
  child.cmd("Logpose projects")
  on("acme")
  child.type_keys("n")
  eq(child.api.nvim_buf_get_name(0), root .. "/projects/acme.md")
end

T["manager"]["t and o search its tasks and to-dos apart; f opens its notes"] = function()
  task("a", "acme")
  H.write(root .. "/meetings/acme/2026-10-14 - retro.md", '---\ntitle: "Retro"\nproject: acme\n---\n- [ ] ship it\n')
  child.lua([[vim.ui.select = function(items, o, cb) table.insert(_G.seen, { o.prompt, #items }); cb(nil) end]])
  child.lua("_G.seen = {}")
  for _, key in ipairs({ "t", "o" }) do
    child.cmd("Logpose projects")
    on("acme")
    child.type_keys(key)
  end
  eq(child.lua_get("_G.seen"), {
    { "Tasks open project:acme", 1 },
    { "To-dos open project:acme", 1 },
  })
  child.cmd("Logpose projects")
  on("acme")
  child.type_keys("f")
  eq(child.bo.filetype, "logpose-notes")
end

T["merge"] = MiniTest.new_set()

T["merge"]["M folds a project into another: tasks, meetings, links; the old page is archived"] = function()
  task("landing", "acme-web", "todo")
  task("api", "acme", "todo")
  page("acme")
  page("acme-web")
  H.write(
    root .. "/meetings/acme-web/2026-10-01 - kickoff.md",
    "---\ntype: adhoc\ndate: 2026-10-01\nproject: acme-web\nseries: acme-web/kickoff\n---\n## Notes\n"
  )
  H.write(
    root .. "/meetings/acme/2026-10-14 - retro.md",
    "---\ntype: retro\ndate: 2026-10-14\nproject: acme\n---\n## Notes\n\n"
      .. "See [[meetings/acme-web/2026-10-01 - kickoff|kickoff]] and [[projects/acme-web|the old page]].\n"
  )
  child.cmd("Logpose project acme-web")
  child.cmd("Logpose projects")
  on("acme-web")
  child.lua("_G.pick('acme', 'Apply')")
  child.type_keys("M") -- choose acme; the preview's Apply is picked too
  eq(project_of("landing"), "acme")
  eq(vim.fn.filereadable(root .. "/meetings/acme/2026-10-01 - kickoff.md"), 1)
  eq(vim.fn.isdirectory(root .. "/meetings/acme-web"), 0)
  local retro = H.read(root .. "/meetings/acme/2026-10-14 - retro.md")
  H.contains(retro, "[[meetings/acme/2026-10-01 - kickoff|kickoff]]")
  H.contains(retro, "[[projects/acme-web|the old page]]") -- the old page stays, so this still works
  local old = H.read(root .. "/projects/acme-web.md")
  H.contains(old, "project: acme-web")
  H.contains(old, "archived: true\nmerged_into: acme")
  H.contains(H.read(root .. "/meetings/acme/2026-10-01 - kickoff.md"), "series: acme/kickoff")
  eq(child.lua_get("require('logpose.state').get('project')"), "acme")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "acme", "none", "auto" })
end

T["merge"]["rename refuses an existing project and points at merge"] = function()
  page("acme")
  page("web")
  local ok, err = pcall(function()
    child.lua(("require('logpose.maintenance').plan_project(%q, 'web', 'acme')"):format(root))
  end)
  eq(ok, false)
  H.contains(err, "merge-project combines two projects")
  ok, err = pcall(function()
    child.lua(("require('logpose.maintenance').plan_project(%q, 'acme', 'acme', { merge = true })"):format(root))
  end)
  eq(ok, false)
  H.contains(err, "same project")
end

return T

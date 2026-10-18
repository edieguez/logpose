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
    end,
    post_once = child.stop,
  },
})

local function task(name, project, status, extra)
  H.write(
    root .. "/tasks/" .. name .. ".md",
    ("---\ntitle: %q\nstatus: %s\nproject: %s\n%s---\n## Context\n"):format(
      name,
      status or "in-progress",
      project,
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

--- Board cards as "title" strings.
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

T["switching"] = MiniTest.new_set()

T["switching"][":Logpose project completes projects that only exist in task files and pages"] = function()
  task("a", "logpose")
  task("b", "hiraishin")
  page("thesis")
  page("old", "archived: true\n")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "hiraishin", "logpose", "thesis", "none" })
  -- archived projects stay searchable
  eq(child.lua_get(("require('logpose.search').projects(%q, require('logpose.index').build(%q))"):format(root, root)), {
    "hiraishin",
    "logpose",
    "old",
    "thesis",
  })
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

T["manager"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        vim.ui.input = function(_, cb) cb(_G.answer) end
        vim.ui.select = function(items, _, cb) cb(items[1]) end
      ]])
    end,
  },
})

local function on(name)
  child.fn.search("\\<" .. name .. "\\>")
end

T["manager"]["lists projects with their counts and marks the active one"] = function()
  task("a", "acme")
  task("b", "acme", "todo", "blocked: waiting\n")
  task("c", "acme", "done")
  task("d", "thesis", "todo")
  H.write(
    root .. "/meetings/acme/2026-10-14 - retro.md",
    '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\n---\n## Notes\n'
  )
  page("empty")
  child.cmd("Logpose project acme")
  child.cmd("Logpose projects")
  local l = lines()
  eq(l[1], "# Projects")
  H.contains(l[3], "Active: acme (pinned)")
  local acme, thesis, empty
  for _, line in ipairs(l) do
    acme = acme or (line:match("● acme") and line)
    thesis = thesis or (line:match("^    thesis") and line)
    empty = empty or (line:match("^    empty") and line)
  end
  H.contains(acme, "2 open (1 in progress) · 1 blocked · 1 done · 1 meeting")
  H.contains(thesis, "1 open")
  H.contains(empty, "project page only")
  -- <CR> switches
  on("thesis")
  child.type_keys("<CR>")
  eq(child.lua_get("require('logpose.project').current()"), "thesis")
  H.contains(lines()[3], "Active: thesis (pinned)")
  -- c goes back to auto-detect
  child.type_keys("c")
  eq(child.lua_get("require('logpose.state').get('project')"), vim.NIL)
end

T["manager"]["a adds a project as a page, without opening it"] = function()
  child.cmd("Logpose projects")
  H.contains(table.concat(lines(), "\n"), "No projects yet")
  child.lua("_G.answer = 'Thesis Work'")
  child.type_keys("a")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "projects")
  local text = H.read(root .. "/projects/thesis-work.md")
  H.contains(text, 'title: "Thesis Work"')
  H.contains(text, "project: thesis-work")
  eq(child.api.nvim_get_current_line():match("thesis%-work") ~= nil, true)
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "thesis-work", "none" })
end

T["manager"]["D archives a project and U restores it"] = function()
  task("a", "acme")
  task("b", "thesis")
  page("acme")
  child.cmd("Logpose project acme")
  child.cmd("Logpose projects")
  on("acme")
  child.type_keys("D")
  H.contains(H.read(root .. "/projects/acme.md"), "archived: true")
  -- notes and tasks stay; the pin is dropped; it leaves completion
  eq(H.read(root .. "/tasks/a.md"):match("project: acme") ~= nil, true)
  eq(child.lua_get("require('logpose.state').get('project')"), vim.NIL)
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "thesis", "none" })
  local text = table.concat(lines(), "\n")
  H.contains(text, "## Archived (1)  A shows them")
  eq(text:match("\n    acme") == nil, true)
  child.type_keys("A")
  on("acme")
  child.type_keys("U")
  eq(H.read(root .. "/projects/acme.md"):match("archived") == nil, true)
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "acme", "thesis", "none" })
end

T["manager"]["D on a project without a page creates one to hold the flag"] = function()
  task("a", "hiraishin")
  child.cmd("Logpose projects")
  on("hiraishin")
  child.type_keys("D")
  H.contains(H.read(root .. "/projects/hiraishin.md"), "archived: true")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "none" })
end

T["manager"]["R renames everywhere and keeps the screen in step"] = function()
  task("a", "logpose")
  page("logpose")
  child.cmd("Logpose project logpose")
  child.cmd("Logpose projects")
  on("logpose")
  child.lua("_G.answer = 'log-pose'")
  child.type_keys("R")
  H.contains(H.read(root .. "/tasks/a.md"), "project: log-pose")
  eq(vim.fn.filereadable(root .. "/projects/log-pose.md"), 1)
  eq(child.lua_get("require('logpose.state').get('project')"), "log-pose")
  child.cmd("Logpose projects")
  H.contains(table.concat(lines(), "\n"), "● log-pose")
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

return T

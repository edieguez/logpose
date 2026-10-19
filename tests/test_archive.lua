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
      child.lua(("require('logpose').setup({ root = %q })"):format(root))
      H.freeze(child, 2026, 10, 14) -- current week starts 2026-10-12
    end,
    post_once = child.stop,
  },
})

local function p(rel)
  return root .. "/" .. rel
end

--- A task file, done on `done` (or open when nil).
local function task(name, done)
  H.write(
    p("tasks/" .. name .. ".md"),
    ('---\ntitle: "%s"\nstatus: %s\n%s---\n'):format(
      name,
      done and "done" or "todo",
      done and ("done: " .. done .. "\n") or ""
    )
  )
end

local function stub_select(choice)
  child.lua(
    ([[vim.ui.select = function(items, opts, cb) _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false); cb(%q) end]]):format(
      choice
    )
  )
end

T["moves done tasks from past weeks into tasks/archive/<week>/"] = function()
  task("old", "2026-10-02")
  task("older", "2026-09-29")
  task("this-week", "2026-10-13")
  task("open")
  child.cmd("Logpose archive!")
  eq(H.read(p("tasks/old.md")), nil)
  H.contains(H.read(p("tasks/archive/week-2026-09-28/old.md")), 'title: "old"')
  H.contains(H.read(p("tasks/archive/week-2026-09-28/older.md")), 'title: "older"')
  H.contains(H.read(p("tasks/this-week.md")), "status: done") -- the current week stays
  H.contains(H.read(p("tasks/open.md")), "status: todo")
  H.contains(child.notifications()[1].msg, "archived 2 done tasks")
end

T["nothing to archive touches nothing"] = function()
  task("this-week", "2026-10-13")
  child.cmd("Logpose archive!")
  H.contains(child.notifications()[1].msg, "nothing to archive")
  eq(vim.fn.isdirectory(p("tasks/archive")), 0)
end

T["refuses when a task has unsaved changes, moving nothing"] = function()
  task("old", "2026-10-02")
  child.cmd("edit " .. p("tasks/old.md"))
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "unsaved" })
  child.cmd("Logpose archive!")
  H.contains(child.notifications()[1].msg, "unsaved changes")
  H.contains(H.read(p("tasks/old.md")), "status: done")
end

T["a buffer showing the task follows it"] = function()
  task("old", "2026-10-02")
  child.cmd("edit " .. p("tasks/old.md"))
  child.cmd("Logpose archive!")
  eq(child.api.nvim_buf_get_name(0), p("tasks/archive/week-2026-09-28/old.md"))
end

T["preview"] = MiniTest.new_set()

T["preview"]["lists the moves and asks first"] = function()
  task("old", "2026-10-02")
  stub_select("Archive")
  child.cmd("Logpose archive")
  eq(child.lua_get("_G.preview"), {
    "Archive done tasks from before the current week (week of 2026-10-12)",
    "",
    "  → tasks/archive/week-2026-09-28/: old.md",
    "",
    "q: close",
  })
  eq(H.read(p("tasks/old.md")), nil)
end

T["preview"]["cancel moves nothing"] = function()
  task("old", "2026-10-02")
  stub_select("Cancel")
  child.cmd("Logpose archive")
  H.contains(child.notifications()[1].msg, "cancelled")
  H.contains(H.read(p("tasks/old.md")), "status: done")
end

T["sprints"] = MiniTest.new_set()

local function sprints(extra)
  child.lua(
    ([[require('logpose').setup({ root = %q, period = { kind = "sprint", sprint = %s } })]]):format(root, extra)
  )
end

T["sprints"]["go by whole sprints, Thursday to Wednesday"] = function()
  sprints([[{ anchor = "2026-10-01", first_number = 42 }]])
  task("a", "2026-09-17")
  task("b", "2026-09-30")
  task("c", "2026-10-01")
  child.cmd("Logpose archive!")
  H.contains(H.read(p("tasks/archive/sprint-41/a.md")), "done: 2026-09-17")
  H.contains(H.read(p("tasks/archive/sprint-41/b.md")), "done: 2026-09-30")
  H.contains(H.read(p("tasks/c.md")), "done: 2026-10-01")
end

T["sprints"]["sprint 9 is older than sprint 10"] = function()
  sprints([[{ anchor = "2026-10-01", first_number = 9 }]])
  H.freeze(child, 2026, 10, 15) -- first day of sprint 10
  task("old", "2026-10-02")
  child.cmd("Logpose archive!")
  H.contains(H.read(p("tasks/archive/sprint-9/old.md")), "done: 2026-10-02")
end

T["sprints"]["the preview names the current sprint"] = function()
  sprints([[{ anchor = "2026-10-01", first_number = 42 }]])
  task("b", "2026-09-30")
  stub_select("Cancel")
  child.cmd("Logpose archive")
  H.contains(
    table.concat(child.lua_get("_G.preview"), "\n"),
    "before the current sprint (sprint-42 (2026-10-01 – 2026-10-14))"
  )
end

T["weeks can start on Thursday"] = function()
  child.lua(("require('logpose').setup({ root = %q, period = { week_start = 4 } })"):format(root))
  task("wed", "2026-10-07")
  task("thu", "2026-10-08")
  child.cmd("Logpose archive!")
  H.contains(H.read(p("tasks/archive/week-2026-10-01/wed.md")), "done: 2026-10-07")
  H.contains(H.read(p("tasks/thu.md")), "done: 2026-10-08")
end

T["completes as a subcommand"] = function()
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose ", "cmdline"), "archive"), true)
end

return T

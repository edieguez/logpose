local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = { pre_case = child.setup, post_once = child.stop },
})

local function resolve()
  return child.lua_get("{ require('logpose.config').resolve_root() }")
end

T["setup"] = MiniTest.new_set()

T["setup"]["uses defaults without setup()"] = function()
  eq(child.lua_get("require('logpose.config').get().dirs.daily"), "daily")
  eq(child.lua_get("require('logpose.config').get().link_style"), "wiki")
end

T["setup"]["merges nested tables"] = function()
  child.lua([[require("logpose").setup({ dirs = { daily = "notes/daily" } })]])
  eq(child.lua_get("require('logpose.config').get().dirs.daily"), "notes/daily")
  eq(child.lua_get("require('logpose.config').get().dirs.meetings"), "meetings")
end

T["setup"]["replaces lists instead of merging them"] = function()
  child.lua([[require("logpose").setup({ workdays = { 1, 2 } })]])
  eq(child.lua_get("require('logpose.config').get().workdays"), { 1, 2 })
end

T["setup"]["warns about unknown keys"] = function()
  child.lua([[require("logpose").setup({ foo = 1, dirs = { bogus = "x" } })]])
  local notes = child.notifications()
  eq(#notes, 1)
  H.contains(notes[1].msg, "dirs.bogus, foo")
  eq(notes[1].level, child.lua_get("vim.log.levels.WARN"))
end

T["setup"]["accepts valid options silently"] = function()
  child.lua([[require("logpose").setup({ root = "/tmp", link_style = "markdown", workdays = { 1, 3, 5 } })]])
  eq(#child.notifications(), 0)
end

T["setup"]["rejects invalid values"] = function()
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ link_style = "html" })]])
  end, "link_style")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ workdays = { 0 } })]])
  end, "workdays")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ dirs = { daily = 1 } })]])
  end, "dirs.daily")
end

T["setup"]["validates period options"] = function()
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ period = { kind = "sprint" } })]])
  end, "anchor` is required")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ period = { sprint = { anchor = "2026-02-30" } } })]])
  end, "YYYY%-MM%-DD")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ period = { sprint = { anchor = "2026-10-01", length_days = 0 } } })]])
  end, "length_days")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ period = { week_start = 8 } })]])
  end, "week_start")
  MiniTest.expect.error(function()
    child.lua([[require("logpose").setup({ period = { kind = "month" } })]])
  end, "period.kind")
end

T["setup"]["accepts a sprint anchor without warnings"] = function()
  child.lua(
    [[require("logpose").setup({ period = { kind = "sprint", sprint = { anchor = "2026-10-01", first_number = 42 } } })]]
  )
  eq(#child.notifications(), 0)
  eq(child.lua_get("require('logpose.config').get().period.sprint.length_days"), 14)
end

T["resolve_root"] = MiniTest.new_set()

T["resolve_root"]["uses the configured root first"] = function()
  local configured = H.tmpdir()
  local marked = H.journal()
  child.cmd("cd " .. marked)
  child.lua(("require('logpose').setup({ root = %q })"):format(configured .. "/"))
  eq(resolve(), { configured, "config" })
end

T["resolve_root"]["errors when the configured root is missing"] = function()
  child.lua([[require("logpose").setup({ root = "/nonexistent/logpose-journal" })]])
  local res = resolve()
  eq(res[1], vim.NIL)
  H.contains(res[2], "is not a directory")
end

T["resolve_root"]["finds a marker above the current buffer"] = function()
  local journal = H.journal()
  local elsewhere = H.journal()
  child.cmd("cd " .. elsewhere) -- buffer beats cwd
  child.cmd("edit " .. journal .. "/daily/daily-2026-10-14.md")
  eq(resolve(), { journal, "buffer" })
end

T["resolve_root"]["falls back to a marker above cwd"] = function()
  local journal = H.journal()
  vim.fn.mkdir(journal .. "/meetings/sub", "p")
  child.cmd("cd " .. journal .. "/meetings/sub")
  eq(resolve(), { journal, "cwd" })
end

T["resolve_root"]["ignores a bare journal/ directory"] = function()
  local dir = H.tmpdir()
  vim.fn.mkdir(dir .. "/journal", "p")
  child.cmd("cd " .. dir)
  local res = resolve()
  eq(res[1], vim.NIL)
  H.contains(res[2], "run :Logpose init or set `root` in setup()")
end

T["resolve_root"]["uses the root saved by :Logpose init last"] = function()
  local saved = H.tmpdir()
  child.lua(("require('logpose.state').set('root', %q)"):format(saved))
  child.cmd("cd " .. H.tmpdir())
  eq(resolve(), { saved, "saved" })
  -- a marker above cwd still wins
  local marked = H.journal()
  child.cmd("cd " .. marked)
  eq(resolve(), { marked, "cwd" })
end

T["resolve_root"]["ignores a saved root that no longer exists"] = function()
  child.lua("require('logpose.state').set('root', '/nonexistent/logpose-journal')")
  child.cmd("cd " .. H.tmpdir())
  eq(resolve()[1], vim.NIL)
end

T["an unreadable state file is set aside, not overwritten"] = function()
  local path = child.lua_get("require('logpose.state').path()")
  H.write(path, '{"root": "/my/journal", oops')
  child.lua("require('logpose.state').set('recent', {})")
  eq(H.read(path .. ".bad"), '{"root": "/my/journal", oops')
  H.contains(child.notifications()[1].msg, "couldn't be read")
end

T["path joins dirs onto the root"] = function()
  local journal = H.journal()
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  eq(child.lua_get("require('logpose.config').path('tasks')"), journal .. "/tasks")
end

return T

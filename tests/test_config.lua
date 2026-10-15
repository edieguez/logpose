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
  eq(child.lua_get("require('logpose.config').get().dirs.daily"), "journal/daily")
  eq(child.lua_get("require('logpose.config').get().link_style"), "wiki")
end

T["setup"]["merges nested tables"] = function()
  child.lua([[require("logpose").setup({ dirs = { daily = "notes/daily" } })]])
  eq(child.lua_get("require('logpose.config').get().dirs.daily"), "notes/daily")
  eq(child.lua_get("require('logpose.config').get().dirs.meetings"), "journal/meetings")
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
  child.cmd("edit " .. journal .. "/journal/daily/daily-2026-10-14.md")
  eq(resolve(), { journal, "buffer" })
end

T["resolve_root"]["falls back to a marker above cwd"] = function()
  local journal = H.journal()
  vim.fn.mkdir(journal .. "/journal/meetings", "p")
  child.cmd("cd " .. journal .. "/journal/meetings")
  eq(resolve(), { journal, "cwd" })
end

T["resolve_root"]["ignores a bare journal/ directory"] = function()
  local dir = H.tmpdir()
  vim.fn.mkdir(dir .. "/journal", "p")
  child.cmd("cd " .. dir)
  local res = resolve()
  eq(res[1], vim.NIL)
  H.contains(res[2], "set `root` in setup()")
end

T["path joins dirs onto the root"] = function()
  local journal = H.journal()
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  eq(child.lua_get("require('logpose.config').path('inbox')"), journal .. "/journal/INBOX.md")
end

return T

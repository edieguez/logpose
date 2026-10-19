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

local function field(path, key)
  return (H.read(path) or ""):match("\n" .. key .. ": ([^\n]*)")
end

T["new notes get created and modified"] = function()
  child.cmd("Logpose daily")
  local daily = root .. "/daily/daily-2026-10-15.md"
  H.contains(
    H.read(daily),
    "---\ncreated: 2026-10-15T09:05\nmodified: 2026-10-15T09:05\n---\n# 2026-10-15 daily notes\n"
  )
  child.cmd("Logpose meeting retro")
  eq(field(root .. "/meetings/2026-10-15 - retro.md", "created"), "2026-10-15T09:05")
  child.cmd("Logpose note Queue design")
  eq(field(root .. "/notes/queue-design.md", "modified"), "2026-10-15T09:05")
  child.cmd("Logpose project-page acme")
  eq(field(root .. "/projects/acme.md", "created"), "2026-10-15T09:05")
  child.cmd("Logpose capture fix flaky test")
  eq(field(root .. "/tasks/fix-flaky-test.md", "created"), "2026-10-15T09:05")
  eq(field(root .. "/tasks/fix-flaky-test.md", "modified"), "2026-10-15T09:05")
end

T["logpose's own edits bump modified, not created"] = function()
  child.cmd("Logpose capture fix flaky test")
  child.cmd("Logpose daily")
  local task, daily = root .. "/tasks/fix-flaky-test.md", root .. "/daily/daily-2026-10-15.md"
  H.freeze(child, 2026, 10, 16, 14, 20)
  child.lua(("require('logpose.taskfile').set_status(%q, 'todo')"):format(task))
  eq(field(task, "modified"), "2026-10-16T14:20")
  eq(field(task, "created"), "2026-10-15T09:05")
  child.cmd("enew")
  child.cmd("Logpose meeting retro 2026-10-15") -- links itself in that day's daily note
  eq(field(daily, "modified"), "2026-10-16T14:20")
  eq(field(daily, "created"), "2026-10-15T09:05")
end

T["saving a changed note bumps modified; saving an unchanged one doesn't"] = function()
  child.cmd("Logpose note Queue design")
  local path = root .. "/notes/queue-design.md"
  H.freeze(child, 2026, 10, 16, 8, 0)
  child.cmd("write")
  eq(field(path, "modified"), "2026-10-15T09:05")
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "Some thoughts." })
  child.cmd("write")
  eq(field(path, "modified"), "2026-10-16T08:00")
  eq(field(path, "created"), "2026-10-15T09:05")
  -- one undo takes back the edit and the bump together
  child.cmd("undo")
  eq(child.fn.getline(5), "modified: 2026-10-15T09:05")
end

T["notes without the key, and files outside the journal, are left alone"] = function()
  local old = root .. "/notes/old.md"
  H.write(old, "---\ntitle: Old\n---\nbody\n")
  child.cmd("edit " .. old)
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "more" })
  child.cmd("write")
  eq(H.read(old), "---\ntitle: Old\n---\nbody\nmore\n")
  local outside = H.tmpdir() .. "/x.md"
  H.write(outside, "---\nmodified: 2020-01-01T00:00\n---\n")
  child.cmd("edit " .. outside)
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "more" })
  child.cmd("write")
  eq(field(outside, "modified"), "2020-01-01T00:00")
end

T["both can be turned off"] = function()
  setup("{ timestamps = { created = false, modified = false } }")
  child.cmd("Logpose daily")
  eq(H.read(root .. "/daily/daily-2026-10-15.md"):sub(1, 3), "# 2")
  child.cmd("Logpose note Queue design")
  eq(field(root .. "/notes/queue-design.md", "created"), nil)
  child.cmd("Logpose capture task")
  eq(field(root .. "/tasks/task.md", "modified"), nil)
  eq(field(root .. "/tasks/task.md", "created"), "2026-10-15T09:05") -- the board needs it
end

T["date filters use the day a task was created"] = function()
  child.cmd("Logpose capture fix flaky test")
  local n = child.lua_get(([[#vim.tbl_filter(function(it) return it.kind == 'task' end,
    require('logpose.query').filter(require('logpose.index').build(%q),
      require('logpose.query').parse({ 'until:2026-10-15', 'since:2026-10-15' })))]]):format(root))
  eq(n, 1)
end

return T

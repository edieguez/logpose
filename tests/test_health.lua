local H = dofile("tests/helpers.lua")

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = { pre_case = child.setup, post_once = child.stop },
})

local function health()
  child.cmd("checkhealth logpose")
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

T["reports a configured root and its paths"] = function()
  local journal = H.journal()
  vim.fn.mkdir(journal .. "/daily", "p")
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  local out = health()
  H.contains(out, "from setup({ root = ... })")
  H.contains(out, "daily: daily")
  H.contains(out, "meetings: meetings does not exist yet")
  H.contains(out, "vim.ui.select")
end

T["reports the archive period"] = function()
  local journal = H.journal()
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  H.contains(health(), "By week, starting Monday")
  child.lua(
    ("require('logpose').setup({ root = %q, period = { kind = 'sprint', sprint = { anchor = '2026-10-01', first_number = 42 } } })"):format(
      journal
    )
  )
  H.contains(health(), "By sprint (14 days): current is sprint-")
end

T["reports the size of the journal"] = function()
  local journal = H.journal()
  H.write(journal .. "/notes/one.md", "# One\n")
  H.write(journal .. "/notes/two.md", "# Two\n")
  H.write(journal .. "/tasks/fix.md", "---\ntitle: Fix\nstatus: todo\n---\n")
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  local out = health()
  H.contains(out, "2 notes and 1 task, indexed in ")
  if out:find("can't be written to", 1, true) then
    error("a writable journal was reported as read-only:\n" .. out)
  end
end

T["says when the journal can't be written to"] = function()
  local journal = H.journal()
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  vim.fn.setfperm(journal, "r-xr-xr-x")
  local ok, out = pcall(health)
  vim.fn.setfperm(journal, "rwxr-xr-x")
  assert(ok, out)
  H.contains(out, "can't be written to: logpose can't save notes or tasks there")
  H.contains(out, "ls -ld")
end

T["reports a root found from cwd"] = function()
  local journal = H.journal()
  child.cmd("cd " .. journal)
  H.contains(health(), "found by marker above the current directory")
end

T["reports a missing root with advice"] = function()
  child.cmd("cd " .. H.tmpdir())
  local out = health()
  H.contains(out, "journal root not found")
  H.contains(out, "Run :Logpose init")
end

T["reports a root saved by :Logpose init"] = function()
  local journal = H.tmpdir()
  child.lua(("require('logpose.state').set('root', %q)"):format(journal))
  child.cmd("cd " .. H.tmpdir())
  H.contains(health(), "saved by :Logpose init")
end

return T

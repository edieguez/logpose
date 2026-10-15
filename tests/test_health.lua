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
  vim.fn.mkdir(journal .. "/journal/daily", "p")
  child.lua(("require('logpose').setup({ root = %q })"):format(journal))
  local out = health()
  H.contains(out, "from setup({ root = ... })")
  H.contains(out, "daily: journal/daily")
  H.contains(out, "meetings: journal/meetings does not exist yet")
  H.contains(out, "vim.ui.select")
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
  H.contains(out, "setup({ root =")
end

return T

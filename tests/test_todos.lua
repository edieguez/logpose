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
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function buf_lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function note(text)
  local path = root .. "/daily/daily-2026-10-14.md"
  H.write(path, text)
  child.cmd("edit " .. path)
  return path
end

T["parse"] = function()
  local parse = function(s)
    return child.lua_get(("require('logpose.todos').parse(%q)"):format(s))
  end
  eq(parse("- [ ] write tests"), { indent = "", checked = false, text = "write tests" })
  eq(parse("  * [x] done #acme"), { indent = "  ", checked = true, text = "done #acme" })
  eq(parse("+ [X] caps"), { indent = "", checked = true, text = "caps" })
  eq(parse("- plain item"), vim.NIL)
  eq(parse("[ ] no bullet"), vim.NIL)
end

T["check"] = MiniTest.new_set()

T["check"]["checks off the to-do on the line, and again unchecks it; u undoes"] = function()
  note("# d\n\n- [ ] review PR\n- [ ] write ADR\n")
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Logpose check")
  eq(buf_lines()[3], "- [x] review PR")
  H.contains(child.notifications()[1].msg, "1 to-do checked")
  child.cmd("Logpose check")
  eq(buf_lines()[3], "- [ ] review PR")
  H.contains(child.notifications()[2].msg, "1 to-do unchecked")
  child.type_keys("u")
  eq(buf_lines()[3], "- [x] review PR")
end

T["check"]["takes a range, skipping other lines"] = function()
  note("# d\n\n- [ ] a\nplain\n- [x] b\n- [ ] c\n")
  child.cmd("3,6Logpose check")
  eq(buf_lines(), { "# d", "", "- [x] a", "plain", "- [x] b", "- [x] c" })
  H.contains(child.notifications()[1].msg, "2 to-dos checked, skipped 1 other line")
end

T["check"]["works from a visual selection via <Plug>"] = function()
  note("# d\n\n- [ ] a\n- [ ] b\n")
  child.lua("vim.keymap.set('x', 'X', '<Plug>(logpose-check)')")
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.type_keys("Vj", "X")
  eq(buf_lines(), { "# d", "", "- [x] a", "- [x] b" })
end

T["check"]["says when there's no to-do"] = function()
  note("# d\n\nplain\n")
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Logpose check")
  H.contains(child.notifications()[1].msg, "no to-do here")
end

T["done works in a task file only"] = function()
  note("# d\n\n- [ ] a\n")
  child.cmd("Logpose done")
  H.contains(child.notifications()[1].msg, ":Logpose done works in a task file")
  eq(buf_lines()[3], "- [ ] a") -- a to-do isn't touched
end

return T

local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = { pre_case = child.setup, post_once = child.stop },
})

local function write(path, content)
  return child.lua_get(("{ require('logpose.util.fs').write_file(%q, %q) }"):format(path, content))
end

T["write_file"] = MiniTest.new_set()

T["write_file"]["creates parent dirs and writes exact content"] = function()
  local dir = H.tmpdir()
  local path = dir .. "/a/b/note.md"
  eq(write(path, "# hola\n\nmundo\n"), { true })
  eq(H.read(path), "# hola\n\nmundo\n")
end

T["write_file"]["leaves no temp files behind"] = function()
  local dir = H.tmpdir()
  write(dir .. "/note.md", "one\n")
  write(dir .. "/note.md", "two\n")
  eq(vim.fn.readdir(dir), { "note.md" })
  eq(H.read(dir .. "/note.md"), "two\n")
end

T["write_file"]["keeps file permissions"] = function()
  local dir = H.tmpdir()
  local path = dir .. "/script.sh"
  H.write(path, "old\n")
  vim.fn.setfperm(path, "rwxr-x---")
  write(path, "new\n")
  eq(vim.fn.getfperm(path), "rwxr-x---")
end

T["write_file"]["refuses to overwrite a buffer with unsaved changes"] = function()
  local dir = H.tmpdir()
  local path = dir .. "/INBOX.md"
  H.write(path, "on disk\n")
  child.cmd("edit " .. path)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
  local res = write(path, "new\n")
  eq(res[1], false)
  H.contains(res[2], "INBOX.md has unsaved changes")
  eq(H.read(path), "on disk\n")
end

T["write_file"]["reloads a clean buffer showing the file"] = function()
  local dir = H.tmpdir()
  local path = dir .. "/DONE.md"
  H.write(path, "old\n")
  child.cmd("edit " .. path)
  child.cmd("enew") -- buffer stays loaded but hidden
  child.o.hidden = true
  write(path, "new line\n")
  local buf = child.fn.bufnr(path)
  eq(child.api.nvim_buf_get_lines(buf, 0, -1, false), { "new line" })
  eq(child.api.nvim_get_option_value("modified", { buf = buf }), false)
end

T["check_writable reports the first dirty file"] = function()
  local dir = H.tmpdir()
  local a, b = dir .. "/a.md", dir .. "/b.md"
  H.write(a, "a\n")
  H.write(b, "b\n")
  child.o.hidden = true
  child.cmd("edit " .. b)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "dirty" })
  child.cmd("edit " .. a)
  local res = child.lua_get(("{ require('logpose.util.fs').check_writable({ %q, %q }) }"):format(a, b))
  eq(res[1], false)
  H.contains(res[2], "b.md")
end

T["read_lines keeps a trailing empty line"] = function()
  local dir = H.tmpdir()
  H.write(dir .. "/x.md", "a\nb\n")
  eq(child.lua_get(("require('logpose.util.fs').read_lines(%q)"):format(dir .. "/x.md")), { "a", "b", "" })
  eq(child.lua_get(("require('logpose.util.fs').read_lines(%q)"):format(dir .. "/missing.md")), vim.NIL)
end

return T

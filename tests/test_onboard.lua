local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.cmd("cd " .. H.tmpdir()) -- no marker anywhere above cwd
    end,
    post_once = child.stop,
  },
})

local function resolve()
  return child.lua_get("{ require('logpose.config').resolve_root() }")
end

local function answer_input(value)
  child.lua(
    ("vim.ui.input = function(opts, cb) _G.input_opts = { prompt = opts.prompt, default = opts.default, completion = opts.completion }; cb(%s) end"):format(
      vim.inspect(value)
    )
  )
end

local function ls(dir)
  local out = vim.fn.readdir(dir)
  table.sort(out)
  return out
end

T[":Logpose init <dir> scaffolds a new journal and saves it"] = function()
  local dir = H.tmpdir() .. "/journal"
  child.cmd("Logpose init " .. dir)
  eq(ls(dir), { ".logpose", "DONE.md", "INBOX.md", "daily", "meetings" })
  eq(H.read(dir .. "/INBOX.md"), "# INBOX\n")
  eq(resolve(), { dir, "saved" })
  H.contains(child.notifications()[1].msg, "created a journal at")
end

T["accepts paths with spaces and ~"] = function()
  local home = H.tmpdir()
  child.lua(("vim.env.HOME = %q"):format(home))
  child.cmd("Logpose init ~/My Journal")
  eq(resolve(), { home .. "/My Journal", "saved" })
end

T["an existing journal only gets the marker"] = function()
  local dir = H.tmpdir()
  H.write(dir .. "/notes/old.md", "keep\n")
  child.cmd("Logpose init " .. dir)
  eq(ls(dir), { ".logpose", "notes" })
  eq(H.read(dir .. "/notes/old.md"), "keep\n")
  H.contains(child.notifications()[1].msg, "using")
end

T["existing INBOX/DONE are never overwritten"] = function()
  local dir = H.tmpdir()
  H.write(dir .. "/INBOX.md", "# mine\n")
  child.cmd("Logpose init " .. dir)
  eq(H.read(dir .. "/INBOX.md"), "# mine\n")
end

T["without an argument, prompts with ~/journal and dir completion"] = function()
  local dir = H.tmpdir() .. "/prompted"
  answer_input(dir)
  child.cmd("Logpose init")
  local opts = child.lua_get("_G.input_opts")
  eq(opts.prompt, "Journal directory: ")
  eq(opts.default, "~/journal")
  eq(opts.completion, "dir")
  eq(resolve(), { dir, "saved" })
end

T["the prompt defaults to the saved journal"] = function()
  local dir = H.tmpdir()
  child.cmd("Logpose init " .. dir)
  answer_input(nil)
  child.cmd("Logpose init")
  eq(child.lua_get("_G.input_opts.default"), vim.fn.fnamemodify(dir, ":~"))
end

T["cancelling does nothing"] = function()
  answer_input(nil)
  child.cmd("Logpose init")
  eq(resolve()[1], vim.NIL)
  H.contains(child.notifications()[1].msg, "cancelled")
end

T["refuses a file"] = function()
  local file = H.tmpdir() .. "/file.md"
  H.write(file, "x")
  child.cmd("Logpose init " .. file)
  H.contains(child.notifications()[1].msg, "is a file, not a directory")
  eq(resolve()[1], vim.NIL)
end

T["respects custom dirs and markers"] = function()
  child.lua(
    "require('logpose').setup({ root_markers = { '.journal' }, dirs = { daily = 'journal/daily', inbox = 'journal/INBOX.md' } })"
  )
  local dir = H.tmpdir() .. "/j"
  child.cmd("Logpose init " .. dir)
  eq(vim.fn.filereadable(dir .. "/.journal"), 1)
  eq(vim.fn.isdirectory(dir .. "/journal/daily"), 1)
  eq(vim.fn.filereadable(dir .. "/journal/INBOX.md"), 1)
end

T["warns when setup({ root }) points elsewhere"] = function()
  local configured = H.tmpdir()
  child.lua(("require('logpose').setup({ root = %q })"):format(configured))
  child.cmd("Logpose init " .. H.tmpdir() .. "/other")
  local notes = child.notifications()
  H.contains(notes[2].msg, "takes precedence")
  eq(resolve(), { configured, "config" })
end

T["the saved journal works from any buffer"] = function()
  local dir = H.tmpdir() .. "/journal"
  child.cmd("Logpose init " .. dir)
  child.cmd("edit " .. H.tmpdir() .. "/work/main.go")
  child.cmd("Logpose daily")
  H.contains(child.api.nvim_buf_get_name(0), dir .. "/daily/daily-")
end

T["first run from :Logpose meeting creates the journal, then the note"] = function()
  local dir = H.tmpdir() .. "/journal"
  answer_input(dir)
  child.cmd("Logpose meeting retro")
  H.contains(child.lua_get("_G.input_opts.prompt"), "No journal found")
  H.contains(child.api.nvim_buf_get_name(0), dir .. "/meetings/")
end

T["an unknown meeting type fails before any prompt"] = function()
  answer_input("should not be asked")
  child.cmd("Logpose meeting nope")
  eq(child.lua_get("_G.input_opts"), vim.NIL)
  H.contains(child.notifications()[1].msg, 'unknown meeting type "nope"')
end

T["a configured but missing root is an error, not a prompt"] = function()
  child.lua("require('logpose').setup({ root = '/nonexistent/logpose-journal' })")
  answer_input("should not be asked")
  child.cmd("Logpose daily")
  eq(child.lua_get("_G.input_opts"), vim.NIL)
  H.contains(child.notifications()[1].msg, "is not a directory")
end

T["completes directories"] = function()
  local dir = H.tmpdir()
  vim.fn.mkdir(dir .. "/journal-a", "p")
  vim.fn.mkdir(dir .. "/journal-b", "p")
  child.cmd("cd " .. dir)
  eq(child.fn.getcompletion("Logpose init jour", "cmdline"), { "journal-a/", "journal-b/" })
end

return T

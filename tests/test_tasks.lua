local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- no project
      child.lua(("require('logpose').setup({ root = %q, tasks = { mode = 'inbox' } })"):format(root))
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function p(rel)
  return root .. "/" .. rel
end

local function lines(...)
  return table.concat({ ... }, "\n") .. "\n"
end

local function buf_lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

T["parse_task"] = function()
  local parse = function(s)
    return child.lua_get(("require('logpose.tasks').parse_task(%q)"):format(s))
  end
  eq(parse("- [ ] write tests"), { indent = "", checked = false, text = "write tests" })
  eq(parse("  * [x] done #acme"), { indent = "  ", checked = true, text = "done #acme" })
  eq(parse("+ [X] caps"), { indent = "", checked = true, text = "caps" })
  eq(parse("- plain item"), vim.NIL)
  eq(parse("[ ] no bullet"), vim.NIL)
end

T["capture"] = MiniTest.new_set()

T["capture"]["creates INBOX and today's section"] = function()
  child.cmd("Logpose capture Fix flaky test")
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-14", "- [ ] Fix flaky test"))
  H.contains(child.notifications()[1].msg, "captured to INBOX")
end

T["capture"]["tags the active project"] = function()
  local repo = H.tmpdir() .. "/acme-api"
  vim.fn.mkdir(repo .. "/.git", "p")
  child.cmd("edit " .. repo .. "/main.go")
  child.cmd("Logpose capture Fix flaky test")
  child.cmd("Logpose capture Review PR #acme-api")
  eq(
    H.read(p("INBOX.md")),
    lines("# INBOX", "", "## 2026-10-14", "- [ ] Fix flaky test #acme-api", "- [ ] Review PR #acme-api")
  )
end

T["capture"]["appends to an existing section, keeping the rest"] = function()
  H.write(
    p("INBOX.md"),
    lines("# INBOX", "", "## 2026-10-13", "- [ ] old", "", "## 2026-10-14", "- [ ] first", "", "## Someday", "- idea")
  )
  child.cmd("Logpose capture second")
  eq(
    H.read(p("INBOX.md")),
    lines(
      "# INBOX",
      "",
      "## 2026-10-13",
      "- [ ] old",
      "",
      "## 2026-10-14",
      "- [ ] first",
      "- [ ] second",
      "",
      "## Someday",
      "- idea"
    )
  )
end

T["capture"]["follows a newest-first INBOX"] = function()
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-13", "- [ ] b", "", "## 2026-10-12", "- [ ] a"))
  child.cmd("Logpose capture c")
  eq(
    H.read(p("INBOX.md")),
    lines("# INBOX", "", "## 2026-10-14", "- [ ] c", "", "## 2026-10-13", "- [ ] b", "", "## 2026-10-12", "- [ ] a")
  )
end

T["capture"]["appends a new day at the end of an oldest-first INBOX"] = function()
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-12", "- [ ] a", "", "## 2026-10-13", "- [ ] b"))
  child.cmd("Logpose capture c")
  eq(
    H.read(p("INBOX.md")),
    lines("# INBOX", "", "## 2026-10-12", "- [ ] a", "", "## 2026-10-13", "- [ ] b", "", "## 2026-10-14", "- [ ] c")
  )
end

T["capture"]["asks for the text when none is given"] = function()
  child.lua("vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('  from prompt ') end")
  child.cmd("Logpose capture")
  eq(child.lua_get("_G.prompt"), "Capture: ")
  H.contains(H.read(p("INBOX.md")), "- [ ] from prompt\n")
  child.lua("vim.ui.input = function(_, cb) cb(nil) end")
  child.cmd("Logpose capture")
  H.contains(child.notifications()[2].msg, "cancelled")
end

T["capture"]["skips an exact duplicate"] = function()
  child.cmd("Logpose capture same")
  child.cmd("Logpose capture same")
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-14", "- [ ] same"))
  H.contains(child.notifications()[2].msg, "already in today's INBOX")
end

T["capture"]["adds to an unsaved INBOX buffer without losing edits"] = function()
  H.write(p("INBOX.md"), lines("# INBOX"))
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "# INBOX", "typing…" })
  child.cmd("Logpose capture new")
  eq(H.read(p("INBOX.md")), lines("# INBOX"))
  eq(buf_lines(), { "# INBOX", "typing…", "", "## 2026-10-14", "- [ ] new" })
  H.contains(child.notifications()[1].msg, "unsaved")
end

T["capture"]["reloads a clean INBOX buffer"] = function()
  H.write(p("INBOX.md"), lines("# INBOX"))
  child.cmd("edit " .. p("INBOX.md"))
  child.cmd("Logpose capture new")
  eq(buf_lines(), { "# INBOX", "", "## 2026-10-14", "- [ ] new" })
end

T["done"] = MiniTest.new_set()

local INBOX =
  lines("# INBOX", "", "## 2026-10-13", "- [ ] a #acme", "- not a task", "- [ ] b", "", "## 2026-10-14", "- [ ] c")

T["done"]["moves an INBOX task to DONE and saves"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.cmd("Logpose done")
  eq(H.read(p("DONE.md")), lines("# DONE", "", "## 2026-10-14", "- [x] a #acme"))
  eq(
    H.read(p("INBOX.md")),
    lines("# INBOX", "", "## 2026-10-13", "- not a task", "- [ ] b", "", "## 2026-10-14", "- [ ] c")
  )
  H.contains(child.notifications()[1].msg, "1 task done")
end

T["done"]["can be undone in the INBOX buffer"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.cmd("Logpose done")
  child.cmd("undo")
  eq(buf_lines()[4], "- [ ] a #acme")
end

T["done"]["handles a range and skips non-task lines"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.cmd("4,6Logpose done")
  eq(H.read(p("DONE.md")), lines("# DONE", "", "## 2026-10-14", "- [x] a #acme", "- [x] b"))
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-13", "- not a task", "", "## 2026-10-14", "- [ ] c"))
  H.contains(child.notifications()[1].msg, "2 tasks done, skipped 1 non-task line")
end

T["done"]["works from a visual selection via <Plug>"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_win_set_cursor(0, { 6, 0 })
  child.type_keys("V", "3j")
  child.api.nvim_feedkeys(child.api.nvim_replace_termcodes("<Plug>(logpose-done)", true, false, true), "x", false)
  eq(H.read(p("DONE.md")), lines("# DONE", "", "## 2026-10-14", "- [x] b", "- [x] c"))
end

T["done"]["checks off a meeting action item and links it from DONE"] = function()
  local note = p("meetings/2026-10-14 - retro.md")
  H.write(note, lines("# Retro", "", "## Action items", "- [ ] follow up", "- [x] already"))
  child.cmd("edit " .. vim.fn.fnameescape(note))
  child.cmd("4,5Logpose done")
  eq(H.read(note), lines("# Retro", "", "## Action items", "- [x] follow up", "- [x] already"))
  eq(
    H.read(p("DONE.md")),
    lines("# DONE", "", "## 2026-10-14", "- [x] follow up ([[meetings/2026-10-14 - retro|2026-10-14 - retro]])")
  )
  H.contains(child.notifications()[1].msg, "1 task done, 1 already checked")
end

T["done"]["does not save a buffer that already had unsaved edits"] = function()
  local note = p("daily/daily-2026-10-14.md")
  H.write(note, lines("# day", "- [ ] task"))
  child.cmd("edit " .. note)
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# day (edited)" })
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.cmd("Logpose done")
  eq(H.read(note), lines("# day", "- [ ] task"))
  eq(buf_lines(), { "# day (edited)", "- [x] task" })
  eq(child.api.nvim_get_option_value("modified", { buf = 0 }), true)
  H.contains(H.read(p("DONE.md")), "- [x] task ([[daily/daily-2026-10-14|daily-2026-10-14]])")
end

T["done"]["follows a newest-first DONE"] = function()
  H.write(p("DONE.md"), lines("# DONE", "", "## 2026-10-13", "- [x] y", "", "## 2026-10-12", "- [x] x"))
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_win_set_cursor(0, { 9, 0 })
  child.cmd("Logpose done")
  eq(
    H.read(p("DONE.md")),
    lines("# DONE", "", "## 2026-10-14", "- [x] c", "", "## 2026-10-13", "- [x] y", "", "## 2026-10-12", "- [x] x")
  )
end

T["done"]["refuses DONE.md and files outside the journal"] = function()
  H.write(p("DONE.md"), lines("# DONE", "- [x] z"))
  child.cmd("edit " .. p("DONE.md"))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.cmd("Logpose done")
  H.contains(child.notifications()[1].msg, "already in DONE")
  local outside = H.tmpdir() .. "/todo.md"
  H.write(outside, "- [ ] x\n")
  child.cmd("edit " .. outside)
  child.cmd("Logpose done")
  H.contains(child.notifications()[2].msg, "not a journal file")
  eq(H.read(outside), "- [ ] x\n")
end

T["done"]["reports when there's nothing to do"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Logpose done")
  H.contains(child.notifications()[1].msg, "skipped 1 non-task line")
  eq(H.read(p("INBOX.md")), INBOX)
  eq(vim.fn.filereadable(p("DONE.md")), 0)
end

return T

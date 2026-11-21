local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
-- The journal's folder, and the symlink it's set up through (`root`). Notes are opened by their
-- real path, as Neovim 0.12 names a buffer reached through a link anyway.
local real, link

local function setup(extra)
  child.lua(
    ("require('logpose').setup(vim.tbl_extend('force', { root = %q, picker = 'select' }, %s))"):format(
      link,
      extra or "{}"
    )
  )
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      real = H.journal()
      link = H.tmpdir() .. "/journal"
      vim.uv.fs_symlink(real, link)
      child.cmd("cd " .. H.tmpdir()) -- no project here
      setup()
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

T[":Logpose edit and done work on a task opened by its real path"] = function()
  H.write(real .. "/tasks/fix-it.md", '---\ntitle: "Fix it"\nstatus: todo\n---\n## Context\n')
  child.cmd("edit " .. real .. "/tasks/fix-it.md")
  child.cmd("Logpose edit")
  eq(child.bo.filetype, "logpose-edit")
  H.contains(child.api.nvim_win_get_config(0).title[1][1], "Edit task")
  child.cmd("stopinsert")
  child.type_keys("q")
  child.cmd("Logpose done")
  H.contains(last_msg(), "moved to Done")
  H.contains(H.read(real .. "/tasks/fix-it.md"), "status: done")
end

T[":Logpose promote links both ways from the root; checking the to-do finishes the task"] = function()
  setup("{ tasks = { promote_status = 'in-progress' } }")
  H.write(real .. "/notes/ideas.md", '---\ntitle: "Ideas"\n---\n- [ ] write the probe\n')
  child.cmd("edit " .. real .. "/notes/ideas.md")
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.cmd("Logpose promote")
  H.contains(H.read(real .. "/tasks/write-the-probe.md"), "From: [[notes/ideas|Ideas]]")
  eq(child.api.nvim_buf_get_lines(0, 3, 5, false), { "- [ ] write the probe", "  → [[tasks/write-the-probe|task]]" })
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.cmd("Logpose check")
  H.contains(H.read(real .. "/tasks/write-the-probe.md"), "status: done")
end

T["saving a task opened by its real path as done checks its to-do"] = function()
  H.write(real .. "/notes/ideas.md", '---\ntitle: "Ideas"\n---\n- [ ] write the probe\n  → [[tasks/probe|task]]\n')
  H.write(real .. "/tasks/probe.md", '---\ntitle: "Write the probe"\nstatus: in-progress\n---\n')
  child.cmd("edit " .. real .. "/tasks/probe.md")
  child.api.nvim_buf_set_lines(0, 2, 3, false, { "status: done" })
  child.cmd("write")
  child.lua("vim.wait(50)")
  H.contains(H.read(real .. "/notes/ideas.md"), "- [x] write the probe\n")
end

T["backlinks and [[ completion in a note opened by its real path"] = function()
  setup("{ link_style = 'markdown' }")
  H.write(real .. "/notes/queue-design.md", '---\ntitle: "Queue design"\n---\nNotes on queues.\n')
  H.write(real .. "/notes/ideas.md", '---\ntitle: "Ideas"\n---\nSee [Queue design](queue-design.md).\n')
  child.lua([[vim.ui.select = function(items, opts) _G.shown = vim.tbl_map(opts.format_item, items) end]])
  child.cmd("edit " .. real .. "/notes/queue-design.md")
  child.cmd("Logpose backlinks")
  eq(child.lua_get("_G.shown"), { "Ideas: See [Queue design](queue-design.md)." })
  -- links written relative to the note, which doesn't offer itself
  child.cmd("edit " .. real .. "/notes/ideas.md")
  eq(
    child.lua_get(
      [[vim.tbl_map(function(it) return it.textEdit.newText end, require('logpose.completion').items('see [[', 6, 3, 0))]]
    ),
    { "[Queue design](queue-design.md)" }
  )
end

T["project detection sees through links: none in the journal, a folder by either path"] = function()
  vim.fn.mkdir(real .. "/.git", "p") -- the journal is a git repo, which isn't a project
  H.write(real .. "/notes/ideas.md", "# Ideas\n")
  child.cmd("edit " .. real .. "/notes/ideas.md")
  eq(child.lua_get("require('logpose').project()"), vim.NIL)
  local work = H.tmpdir()
  H.write(work .. "/acme-api/main.lua", "print(1)\n")
  vim.uv.fs_symlink(work .. "/acme-api", work .. "/acme")
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(work .. "/acme"))
  child.cmd("edit " .. work .. "/acme-api/main.lua")
  eq(child.lua_get("require('logpose').project()"), "acme")
end

T[":Logpose hub in a project page opened by its real path"] = function()
  H.write(real .. "/projects/acme.md", '---\ntitle: "Acme API"\nproject: acme\n---\n## Overview\n')
  H.write(
    real .. "/projects/acme/use-postgres.md",
    '---\ntitle: "Use Postgres"\ntype: decision\nstatus: accepted\n---\n## Context\n'
  )
  child.cmd("edit " .. real .. "/projects/acme.md")
  child.cmd("Logpose hub")
  H.contains(last_msg(), "updated the hub of acme")
  H.contains(H.read(real .. "/projects/acme.md"), "[[projects/acme/use-postgres|Use Postgres]] · accepted")
end

return T

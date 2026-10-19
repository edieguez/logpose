local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- no project here
      child.o.columns, child.o.lines = 120, 40
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
      H.write(
        root .. "/meetings/acme/2026-10-14 - retro.md",
        '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\nproject: acme\n---\n- [ ] write ADR\n- [ ] ping Ana\n- [x] done\n- see [[fix-ci]]\n'
      )
      H.write(
        root .. "/meetings/thesis/2026-10-10 - advisor.md",
        '---\ntype: 1on1\ndate: 2026-10-10\ntitle: "1:1 Advisor"\nproject: thesis\n---\n'
      )
      H.write(root .. "/notes/queue-design.md", '---\ntitle: "Queue design"\nproject: acme\n---\n')
      H.write(root .. "/daily/daily-2026-10-13.md", "# 2026-10-13 daily notes\n- reviewed #acme PR\n")
      H.write(root .. "/daily/daily-2026-10-12.md", "# 2026-10-12 daily notes\n")
      H.write(root .. "/projects/acme.md", '---\ntitle: "Acme API"\nproject: acme\n---\n')
      H.write(root .. "/tasks/fix-ci.md", '---\ntitle: "Fix CI"\nstatus: todo\nproject: acme\n---\n')
    end,
    post_once = child.stop,
  },
})

local function screen()
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function line_with(s)
  for i, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(s, 1, true) then
      return i
    end
  end
end

T["lists notes by type, newest first, with to-dos and linked tasks; no tasks"] = function()
  child.cmd("Logpose notes")
  eq(child.bo.filetype, "logpose-notes")
  local s = screen()
  H.contains(s, "# Notes · all projects")
  H.contains(s, "## Meetings (2)\n\n  2026-10-14  Retro")
  H.contains(s, "☐ 2 to-dos  ·  → 1 task  ·  ◆ acme")
  H.contains(s, "  2026-10-10  1:1 Advisor")
  H.contains(s, "## Topic notes (1)")
  H.contains(s, "## Daily notes (2)\n\n  2026-10-13  Tuesday")
  H.contains(s, "## Project pages (1)")
  eq(s:find("Fix CI", 1, true), nil) -- tasks are on the board, not here
  -- the cursor starts on the newest note; <CR> opens it
  eq(child.api.nvim_win_get_cursor(0)[1], line_with("Retro"))
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-14 - retro.md")
end

T["a project's notes: by frontmatter or #tag; p toggles all"] = function()
  child.lua("require('logpose.notes.browse').open(..., { project = 'acme' })", { root })
  local s = screen()
  H.contains(s, "# Notes · Acme API")
  H.contains(s, "Retro")
  H.contains(s, "Queue design")
  H.contains(s, "Tuesday") -- the daily note mentioning #acme
  eq(s:find("Advisor", 1, true), nil)
  eq(s:find("Monday", 1, true), nil)
  eq(s:find("◆ acme", 1, true), nil) -- obvious on a one-project screen
  child.type_keys("p")
  H.contains(screen(), "# Notes · all projects")
  H.contains(screen(), "Advisor")
end

T["/ filters with the find filters"] = function()
  child.cmd("Logpose notes")
  child.lua("vim.ui.input = function(o, cb) _G.prompt = o.prompt; cb('type:retro') end")
  child.type_keys("/")
  local s = screen()
  H.contains(s, "filter: type:retro")
  H.contains(s, "## Meetings (1)")
  eq(s:find("Daily notes", 1, true), nil)
  child.lua("vim.ui.input = function(o, cb) cb('nothing-matches-this') end")
  child.type_keys("/")
  H.contains(screen(), "no notes match the filter")
  -- filters given on the command line
  child.cmd("Logpose notes #acme")
  H.contains(screen(), "filter: #acme")
  H.contains(screen(), "## Daily notes (1)")
end

T["g groups by project; z folds; long sections show more on demand"] = function()
  for d = 1, 9 do
    H.write(root .. ("/daily/daily-2026-09-%02d.md"):format(d), "# d\n")
  end
  child.cmd("Logpose notes")
  H.contains(screen(), "## Daily notes (11)")
  H.contains(screen(), "… 3 more (<CR> to show all)")
  child.api.nvim_win_set_cursor(0, { line_with("… 3 more"), 0 })
  child.type_keys("<CR>")
  eq(screen():find("more (<CR>", 1, true), nil)
  child.api.nvim_win_set_cursor(0, { line_with("## Meetings"), 0 })
  child.type_keys("z")
  H.contains(screen(), "▸ ## Meetings (2)")
  eq(screen():find("Retro", 1, true), nil)
  child.type_keys("g")
  local s = screen()
  H.contains(s, "## Acme API (3)")
  H.contains(s, "retro · Retro")
  H.contains(s, "note · Queue design")
  H.contains(s, "## No project (")
  eq(s:find("## No project", 1, true) > s:find("## thesis", 1, true), true) -- no project last
  eq(s:find("[ \t]\n") ~= nil, false) -- no trailing spaces
end

T["e edits the note's details and the screen follows"] = function()
  child.cmd("Logpose notes")
  child.api.nvim_win_set_cursor(0, { line_with("Queue design"), 0 })
  child.type_keys("e")
  eq(child.bo.filetype, "logpose-edit")
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "Queue design v2" })
  child.cmd("write")
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-notes")
  H.contains(screen(), "Queue design v2")
end

T["f on the projects screen opens it for that project"] = function()
  child.cmd("Logpose projects")
  child.api.nvim_win_set_cursor(0, { line_with("Acme API"), 0 })
  child.type_keys("f")
  eq(child.bo.filetype, "logpose-notes")
  H.contains(screen(), "# Notes · Acme API")
end

T["completes find filters"] = function()
  local c = child.fn.getcompletion("Logpose notes type:", "cmdline")
  eq(vim.tbl_contains(c, "type:retro"), true)
end

return T

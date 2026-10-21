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
      child.o.columns, child.o.lines = 140, 40
      child.lua(
        ("require('logpose').setup({ root = %q, picker = 'select', people = { contacts = { slack = { label = 'Slack', show = '@{value}', order = 2 } } } })"):format(
          root
        )
      )
      H.freeze(child, 2026, 10, 15)
      H.write(
        root .. "/people/ana-lopez.md",
        '---\nname: "Ana López"\naliases: [Ana]\nrole: Backend lead\nprojects: [acme]\nemail: ana@acme.io\nslack: ana.l\n---\n## Notes\n'
      )
      H.write(root .. "/people/carla.md", '---\nname: "Carla"\nrole: PM\n---\n## Notes\n')
      H.write(
        root .. "/meetings/acme/2026-10-14 - retro.md",
        '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\nproject: acme\nattendees: [Ana, Bob Smith]\n---\n- [ ] fix CI @ana\n- [x] old @ana\n'
      )
      H.write(
        root .. "/meetings/acme/2026-10-07 - 1-1-ana.md",
        '---\ntype: 1on1\ndate: 2026-10-07\ntitle: "1:1 Ana"\nproject: acme\nwith: Ana\n---\n'
      )
      H.write(root .. "/tasks/fix-ci.md", '---\ntitle: "Fix CI"\nstatus: todo\nproject: acme\n---\nAsk @ana\n')
    end,
    post_once = child.stop,
  },
})

--- The window's top bar, without highlights.
local function bar()
  return (child.wo.winbar:gsub("%%#[^#]*#", ""))
end

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

T["lists people with a page, then the ones your notes mention"] = function()
  child.cmd("Logpose people")
  eq(child.bo.filetype, "logpose-people")
  local s = screen()
  H.contains(bar(), "People · all projects")
  H.contains(s, "▾ With a page  2")
  local ana = child.api.nvim_buf_get_lines(0, line_with("Ana López") - 1, line_with("Ana López"), false)[1]
  H.contains(ana, "Backend lead")
  H.contains(ana, "ana@acme.io · @ana.l")
  H.contains(ana, "met yesterday")
  H.contains(ana, "☐ 1 open")
  H.contains(ana, "◆ acme")
  -- met recently first; Carla, never met, after
  eq(line_with("Ana López") < line_with("Carla"), true)
  H.contains(s, "▾ In your notes, no page yet  1")
  H.contains(s, "Bob Smith")
  H.contains(s, "1 mention")
  eq(child.api.nvim_win_get_cursor(0)[1], line_with("Ana López"))
end

T["<Tab> shows what involves them; <CR> opens it"] = function()
  child.cmd("Logpose people")
  child.type_keys("<Tab>")
  local s = screen()
  H.contains(s, "◷ ")
  H.contains(s, "Retro")
  H.contains(s, "1:1 Ana")
  H.contains(s, "☐ fix CI @ana")
  H.contains(s, "▣ Fix CI")
  eq(line_with("Retro") < line_with("1:1 Ana"), true) -- newest meeting first
  child.api.nvim_win_set_cursor(0, { line_with("▣ Fix CI"), 0 })
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "fix-ci.md")
end

T["<CR> opens the page; on someone without one, the form to add it"] = function()
  child.cmd("Logpose people")
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "ana-lopez.md")
  child.cmd("Logpose people")
  child.api.nvim_win_set_cursor(0, { line_with("Bob Smith"), 0 })
  child.type_keys("<CR>")
  H.contains(child.api.nvim_buf_get_lines(0, 0, 1, false)[1], "Bob Smith")
end

T["/ filters by name, role, project or any field; p toggles the project"] = function()
  child.cmd("Logpose people pm")
  local s = screen()
  H.contains(s, "Carla")
  eq(s:find("Ana López", 1, true), nil)
  child.cmd("Logpose people slack:* or role:pm")
  s = screen()
  H.contains(s, "Carla")
  H.contains(s, "Ana López")
  eq(s:find("Bob Smith", 1, true), nil)
  child.cmd("Logpose people date>=2026-10-10")
  s = screen()
  H.contains(s, "Ana López") -- met on the 14th
  eq(s:find("Carla", 1, true), nil)
  child.lua("require('logpose.lists').open(..., require('logpose.lists.people'), { project = 'acme' })", { root })
  s = screen()
  H.contains(bar(), "People · acme")
  H.contains(s, "Ana López")
  eq(s:find("Carla", 1, true), nil)
  child.type_keys("p")
  H.contains(screen(), "Carla")
end

T["y copies a way to reach them, choosing when there are several"] = function()
  child.lua([[
    vim.ui.select = function(items, opts, cb)
      _G.offered = vim.tbl_map(opts.format_item, items)
      cb(items[2])
    end
  ]])
  child.cmd("Logpose people")
  child.type_keys("y")
  eq(child.lua_get("_G.offered"), { "Email: ana@acme.io", "Slack: @ana.l" })
  eq(child.fn.getreg('"'), "ana.l")
  child.lua("vim.ui.open = function(url) _G.opened = url end")
  child.type_keys("o") -- only email opens
  eq(child.lua_get("_G.opened"), "mailto:ana@acme.io")
end

T[":Logpose person opens a page by any of their names"] = function()
  child.cmd("Logpose person ana")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "ana-lopez.md")
  eq(child.lua_get("vim.fn.getcompletion('Logpose person ca', 'cmdline')"), { "carla" })
  eq(child.lua_get("vim.fn.getcompletion('Logpose person ana', 'cmdline')"), { "ana-lopez" })
end

T["gx on an @mention or an attendee opens their page"] = function()
  local retro = root .. "/meetings/acme/2026-10-14 - retro.md"
  local function gx(row, col)
    child.cmd("edit " .. vim.fn.fnameescape(retro))
    child.bo.filetype = "markdown"
    child.api.nvim_win_set_cursor(0, { row, col })
    child.type_keys("gx")
    return vim.fs.basename(child.api.nvim_buf_get_name(0))
  end
  eq(gx(8, 14), "ana-lopez.md") -- on @ana
  eq(gx(6, 13), "ana-lopez.md") -- attendees: [Ana, …]
  eq(gx(6, 19), "2026-10-14 - retro.md") -- Bob Smith: no page, nothing to open
end

T["rename-person: the page moves, keeps the old name, and notes follow"] = function()
  H.write(root .. "/notes/team.md", "# Team\n- [[people/ana-lopez|Ana]] leads, @ana.\n- @analyst stays\n")
  child.cmd("Logpose rename-person! ana Ana García")
  eq(vim.fn.filereadable(root .. "/people/ana-lopez.md"), 0)
  local page = H.read(root .. "/people/ana-garcia.md")
  H.contains(page, "name: Ana García\n")
  H.contains(page, "aliases: [Ana, Ana López]")
  H.contains(page, "slack: ana.l")
  local retro = H.read(root .. "/meetings/acme/2026-10-14 - retro.md")
  H.contains(retro, "attendees: [Ana García, Bob Smith]")
  H.contains(retro, "- [ ] fix CI @ana-garcia")
  H.contains(H.read(root .. "/meetings/acme/2026-10-07 - 1-1-ana.md"), "with: Ana García")
  eq(H.read(root .. "/notes/team.md"), "# Team\n- [[people/ana-garcia|Ana]] leads, @ana-garcia.\n- @analyst stays\n")
  -- still one person, under the new name
  child.cmd("Logpose people")
  H.contains(screen(), "Ana García")
  eq(screen():find("Ana López", 1, true), nil)
end

T["by project or role; moving changes their page"] = function()
  child.cmd("Logpose people")
  child.type_keys("g")
  local s = screen()
  H.contains(s, "▾ acme  2") -- Ana (page) and Bob (mentioned)
  H.contains(s, "▾ No project  1")
  child.type_keys("g")
  H.contains(screen(), "▾ Backend lead  1")
  child.api.nvim_win_set_cursor(0, { line_with("  Carla"), 2 })
  child.lua("vim.ui.input = function(o, cb) cb('Product manager') end")
  child.lua([[vim.ui.select = function(items, opts, cb)
    for _, it in ipairs(items) do if opts.format_item(it) == "new…" then return cb(it) end end
  end]])
  child.type_keys("m")
  H.contains(H.read(root .. "/people/carla.md"), "role: Product manager")
  H.contains(screen(), "▾ Product manager  1")
  -- someone without a page can't be moved: add one first
  child.api.nvim_win_set_cursor(0, { line_with("  Bob Smith"), 2 })
  child.type_keys("m")
  H.contains(child.notifications()[#child.notifications()].msg, "Bob Smith has no page yet")
end

T["1 starts a 1:1 with them"] = function()
  child.cmd("Logpose people")
  child.type_keys("1")
  local form = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(form, "Ana López")
end

return T

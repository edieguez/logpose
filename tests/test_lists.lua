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
      child.o.columns, child.o.lines = 140, 50
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
      H.write(
        root .. "/meetings/acme/2026-10-14 - retro.md",
        '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\nproject: acme\nattendees: [Ana, Bob Smith]\nroom: Lisboa\n---\n- [ ] write ADR @ana\n- [x] done\n- see [[tasks/fix-ci]]\n'
      )
      H.write(
        root .. "/meetings/acme/2026-10-05 - planning.md",
        '---\ntype: planning\ndate: 2026-10-05\ntitle: "Planning"\nproject: acme\nattendees: [Carla]\n---\n'
      )
      H.write(
        root .. "/meetings/thesis/2026-10-13 - advisor.md",
        '---\ntype: 1on1\ndate: 2026-10-13\ntitle: "1:1 Advisor"\nproject: thesis\nwith: Ana\n---\n'
      )
      H.write(
        root .. "/notes/queue-design.md",
        '---\ntitle: "Queue design"\nproject: acme\ntags: [arch, perf]\n---\n- [ ] benchmark\n'
      )
      H.write(root .. "/notes/reading.md", '---\ntitle: "Reading list"\ntags: [books]\n---\n')
      H.write(root .. "/daily/daily-2026-10-13.md", "# 2026-10-13 daily notes\n- reviewed #acme PR\n")
      H.write(root .. "/projects/acme.md", '---\ntitle: "Acme API"\nproject: acme\n---\n')
      H.write(root .. "/tasks/fix-ci.md", '---\ntitle: "Fix CI"\nstatus: todo\nproject: acme\n---\n')
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

local function on(s)
  child.api.nvim_win_set_cursor(0, { line_with(s), 2 })
end

local function pick(label)
  child.lua(([[vim.ui.select = function(items, opts, cb)
    _G.offered = vim.tbl_map(opts.format_item, items)
    for _, it in ipairs(items) do if opts.format_item(it) == %q then return cb(it) end end
    cb(nil)
  end]]):format(label))
end

T["meetings"] = MiniTest.new_set()

T["meetings"]["by week, newest first, with people, action items and tasks"] = function()
  child.cmd("Logpose meetings")
  eq(child.bo.filetype, "logpose-meetings")
  local s = screen()
  H.contains(bar(), "Meetings · all projects")
  H.contains(bar(), "3 meetings · by week · newest first · ? help")
  H.contains(s, "▾ Week of Mon 12 Oct · this week  2")
  H.contains(s, "▾ Week of Mon 5 Oct · last week  1")
  local retro = child.api.nvim_buf_get_lines(0, line_with("Retro") - 1, line_with("Retro"), false)[1]
  H.contains(retro, "Yesterday   Retrospective    Retro")
  H.contains(retro, "Ana, Bob  ·  ☐ 1 open  ·  → 1 task  ·  ◆ acme")
  eq(line_with("Retro") < line_with("1:1 Advisor"), true)
  eq(line_with("Week of Mon 12") < line_with("Week of Mon 5"), true)
  eq(s:find("Queue design", 1, true), nil) -- notes have their own list
  eq(s:find("[ \t]\n") ~= nil, false) -- no trailing spaces
  -- <Tab>: who, action items, tasks; <CR> on one opens it there
  on("Retro")
  child.type_keys("<Tab>")
  s = screen()
  H.contains(s, "with Ana, Bob Smith")
  H.contains(s, "☐ write ADR @ana")
  H.contains(s, "☑ 1 done")
  H.contains(s, "▣ Fix CI  TODO")
  on("☐ write ADR")
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-14 - retro.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 9)
end

T["meetings"]["filters: or, frontmatter fields, attendees, dates"] = function()
  local function shown(filter)
    child.cmd("Logpose meetings " .. filter)
    local out = {}
    for _, t in ipairs({ "Retro", "Planning", "1:1 Advisor" }) do
      if line_with("  " .. t) or line_with(" " .. t .. " ") then
        table.insert(out, t)
      end
    end
    return out
  end
  eq(shown("type:retro or type:planning"), { "Retro", "Planning" })
  eq(shown("attendees:ana"), { "Retro" })
  eq(shown("@ana"), { "Retro", "1:1 Advisor" })
  eq(shown("room:lisboa"), { "Retro" })
  eq(shown("date>=2026-10-13"), { "Retro", "1:1 Advisor" })
  eq(shown("date:2026-10-01..2026-10-10"), { "Planning" })
  eq(shown("-project:acme"), { "1:1 Advisor" })
  eq(shown("(type:1on1 or #nothing) or attendees:carla"), { "Planning", "1:1 Advisor" })
end

T["meetings"]["g groups by type, project, series; moving changes the note"] = function()
  child.cmd("Logpose meetings")
  child.type_keys("g")
  local s = screen()
  H.contains(s, "▾ Retrospective  1")
  H.contains(s, "▾ Sprint planning  1")
  -- another type: the note's type changes
  on("Yesterday")
  pick("Sprint review")
  child.type_keys("m")
  H.contains(H.read(root .. "/meetings/acme/2026-10-14 - retro.md"), "type: review")
  H.contains(screen(), "▾ Sprint review  1")
  -- by project: moving to another project moves the file
  child.type_keys("g")
  H.contains(screen(), "▾ Acme API  2")
  on("Planning")
  pick("thesis")
  child.type_keys("m")
  eq(vim.fn.filereadable(root .. "/meetings/thesis/2026-10-05 - planning.md"), 1)
  H.contains(H.read(root .. "/meetings/thesis/2026-10-05 - planning.md"), "project: thesis")
  H.contains(screen(), "▾ thesis  2")
  -- < and > move to the neighbouring group
  on("Planning")
  child.type_keys("<")
  H.contains(H.read(root .. "/meetings/acme/2026-10-05 - planning.md"), "project: acme")
  -- by series, then week: worked out from the note, can't be moved to
  child.type_keys("g")
  H.contains(screen(), "▾ Not in a series  3")
  child.type_keys("g")
  H.contains(bar(), "by week")
  on("Planning")
  child.type_keys("m")
  H.contains(child.notifications()[#child.notifications()].msg, "grouped by week, which comes from the note itself")
end

T["meetings"]["a starts a meeting of the group's type"] = function()
  child.cmd("Logpose meetings")
  child.type_keys("g")
  on("Retro")
  child.type_keys("a")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New meeting ")
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "retro")
end

T["meetings"]["/ opens the filter bar: the list follows, a menu shows what to type"] = function()
  child.cmd("Logpose meetings")
  child.type_keys("/")
  eq(child.bo.filetype, "logpose-filter")
  vim.loop.sleep(60)
  -- an empty bar offers the filters, each with what it does
  eq(child.fn.pumvisible(), 1)
  local words = child.lua_get("vim.tbl_map(function(i) return i.word end, vim.fn.complete_info({ 'items' }).items)")
  eq(vim.tbl_contains(words, "type:"), true)
  eq(vim.tbl_contains(words, "attendees:"), true)
  eq(vim.tbl_contains(words, "room:"), true) -- fields your notes use
  child.type_keys("type:")
  vim.loop.sleep(60)
  local items = child.lua_get("vim.fn.complete_info({ 'items' }).items")
  local retro
  for _, i in ipairs(items) do
    if i.word == "type:retro" then
      retro = i
    end
  end
  eq(retro.menu, "Retrospective")
  child.type_keys("retro")
  vim.loop.sleep(120)
  -- the list behind follows; the bar's edge counts
  local behind =
    table.concat(child.lua_get("vim.api.nvim_buf_get_lines(vim.fn.bufnr('logpose://meetings'), 0, -1, false)"), "\n")
  eq(behind:find("Planning", 1, true), nil)
  H.contains(behind, "Retro")
  H.contains(child.lua_get("vim.api.nvim_win_get_config(0).footer[1][1]"), "1 meeting")
  child.type_keys("<CR>")
  eq(child.bo.filetype, "logpose-meetings")
  H.contains(bar(), "type:retro")
  -- half-typed words are ignored, and the bar says so
  child.type_keys("/", " since:2026-1")
  vim.loop.sleep(120)
  H.contains(child.lua_get("vim.api.nvim_win_get_config(0).footer[1][1]"), "ignored: since:2026-1")
  child.type_keys("<Esc>", "<Esc>")
  eq(child.bo.filetype, "logpose-meetings")
  H.contains(bar(), "type:retro") -- <Esc>: the filter as it was
  child.type_keys("<BS>")
  eq(bar():find("type:retro", 1, true), nil)
end

T["meetings"]["? shows the keys and the filter cheat sheet"] = function()
  child.cmd("Logpose meetings")
  child.type_keys("?")
  local help = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(help, "group by: week · type · project · series")
  H.contains(help, "date:2026-10-01..2026-10-15")
  H.contains(help, "a or b")
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-meetings")
end

T["filter completion knows the journal"] = function()
  local function words(token)
    return child.lua_get(
      ("vim.tbl_map(function(i) return i.word end, require('logpose.filter').complete(%q))"):format(token)
    )
  end
  eq(vim.tbl_contains(words("attendees:"), "attendees:ana"), true)
  eq(vim.tbl_contains(words("@bo"), "@bob-smith"), true)
  eq(vim.tbl_contains(words("-#"), "-#arch"), true)
  eq(words("room:"), { "room:Lisboa", "room:*" })
  eq(vim.tbl_contains(words("date>="), "date>=today"), true)
  eq(vim.tbl_contains(words("has:"), "has:attendees"), true)
  eq(vim.tbl_contains(words("type:da"), "type:daily"), true)
  eq(words("pro"), { "project:" })
  -- and on the command line
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose find meetings attendees:", "cmdline"), "attendees:ana"), true)
end

T["notes"] = MiniTest.new_set()

T["notes"]["topic notes and project pages by type; daily notes and meetings on request"] = function()
  child.cmd("Logpose notes")
  eq(child.bo.filetype, "logpose-notes")
  local s = screen()
  H.contains(s, "▾ Topic notes  2")
  H.contains(s, "▾ Project pages  1")
  H.contains(s, "Queue design")
  H.contains(s, "☐ 1 to-do  ·  ◆ acme  ·  #arch #perf")
  eq(s:find("Daily notes", 1, true), nil)
  eq(s:find("Retro", 1, true), nil)
  eq(s:find("Fix CI", 1, true), nil)
  child.cmd("Logpose notes type:daily")
  s = screen()
  H.contains(s, "▾ Daily notes  1")
  eq(s:find("Queue design", 1, true), nil)
  child.cmd("Logpose notes type:daily or #books")
  s = screen()
  H.contains(s, "Daily notes  1")
  H.contains(s, "Reading list")
end

T["notes"]["by tag: a note under each tag; moving swaps the tag"] = function()
  child.cmd("Logpose notes")
  child.type_keys("g", "g")
  local s = screen()
  H.contains(s, "▾ #arch  1")
  H.contains(s, "▾ #perf  1")
  H.contains(s, "▾ #books  1")
  H.contains(s, "▾ No tags  1") -- the project page
  child.api.nvim_win_set_cursor(0, { line_with("▾ #perf") + 1, 2 })
  child.lua("vim.ui.input = function(o, cb) cb('design') end")
  pick("new…")
  child.type_keys("m")
  H.contains(H.read(root .. "/notes/queue-design.md"), "tags: [arch, design]")
  H.contains(screen(), "▾ #design  1")
end

T["notes"]["by project: moving sets the project; p for this project only"] = function()
  child.cmd("Logpose notes")
  child.type_keys("g")
  on("Reading list")
  pick("Acme API")
  child.type_keys("m")
  H.contains(H.read(root .. "/notes/reading.md"), "project: acme")
  -- a project page stays with its project
  on("  Acme API")
  pick("thesis")
  child.type_keys("m")
  H.contains(child.notifications()[#child.notifications()].msg, "a project page belongs to its project")
  child.lua("require('logpose.lists').open(..., require('logpose.lists.notes'), { project = 'thesis' })", { root })
  H.contains(bar(), "Notes · thesis")
  H.contains(screen(), "No notes yet")
  child.type_keys("p")
  H.contains(bar(), "Notes · all projects")
end

T["notes"]["z folds, … more, ]] jumps, s orders, K peeks, e edits"] = function()
  for d = 1, 12 do
    H.write(root .. ("/notes/n%02d.md"):format(d), ('---\ntitle: "Note %02d"\n---\n'):format(d))
  end
  child.cmd("Logpose notes")
  H.contains(screen(), "▾ Topic notes  14")
  H.contains(screen(), "… 4 more  <CR>")
  on("… 4 more")
  child.type_keys("<CR>")
  eq(screen():find("more  <CR>", 1, true), nil)
  on("▾ Topic notes")
  child.type_keys("z")
  H.contains(screen(), "▸ Topic notes  14")
  child.type_keys("]]")
  eq(child.api.nvim_win_get_cursor(0)[1], line_with("▾ Project pages"))
  child.type_keys("s", "s")
  H.contains(bar(), "by title")
  on("Acme API")
  child.type_keys("K")
  eq(child.api.nvim_win_get_config(0).relative, "editor")
  child.type_keys("q")
  child.type_keys("e")
  eq(child.bo.filetype, "logpose-edit")
end

T["notes"]["f on the projects screen opens the project's notes"] = function()
  child.cmd("Logpose projects")
  on("Acme API")
  child.type_keys("f")
  eq(child.bo.filetype, "logpose-notes")
  H.contains(bar(), "Notes · Acme API")
end

return T

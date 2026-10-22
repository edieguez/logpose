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
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
    end,
    post_once = child.stop,
  },
})

local TASK = "---\n"
  .. 'title: "Fix flaky test"\n'
  .. "status: todo\nproject: acme\ntags: [ci]\ndue:\nblocked:\n"
  .. "created: 2026-10-14T09:00\nmodified: 2026-10-14T09:00\n---\n"
  .. "## Context\n\n## Log\n\n- 2026-10-14 09:00: created in Backlog\n"

--- The form's values, one per field.
local function values()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- What the form draws: per row its label and end-of-line text, and the lines below it.
local function drawn()
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local rows, below = {}, {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local row, d = m[2] + 1, m[4]
      rows[row] = rows[row] or { label = "", eol = "" }
      local text = table.concat(vim.tbl_map(function(c) return c[1] end, d.virt_text or {}))
      if d.virt_text_pos == "inline" then
        rows[row].label = vim.trim(text)
      elseif d.virt_text_pos == "eol" then
        rows[row].eol = vim.trim(text)
      end
      for _, vl in ipairs(d.virt_lines or {}) do
        local l = vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, vl)))
        if l ~= "" then
          table.insert(below, l)
        end
      end
    end
    return { rows = rows, below = below }
  end)()]])
end

--- Set the value on the row of field `key`.
local function set(key, value)
  local d = drawn()
  for row, r in pairs(d.rows) do
    if r.label == key then
      child.api.nvim_buf_set_lines(0, row - 1, row, false, { value })
      child.lua(
        "require('logpose.edit.form').render(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])"
      )
      return
    end
  end
  error("no field " .. key)
end

--- Put the cursor on field `key`.
local function on(key)
  for row, r in pairs(drawn().rows) do
    if r.label == key then
      child.api.nvim_win_set_cursor(0, { row, 0 })
      return
    end
  end
  error("no field " .. key)
end

local function edit(path)
  child.cmd("edit " .. path)
  child.cmd("Logpose edit")
end

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

T["the form: values only, field names beside them, hints, logpose's own fields below"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  eq(child.bo.filetype, "logpose-edit")
  eq(values(), { "Fix flaky test", "todo", "acme", "ci", "", "" })
  local d = drawn()
  eq(
    vim.tbl_map(function(r)
      return r.label
    end, d.rows),
    { "title", "status", "project", "tags", "due", "blocked" }
  )
  H.contains(d.rows[5].eol, "today, fri, +3d") -- a hint in the empty due field
  H.contains(d.rows[6].eol, "waiting on")
  eq(d.below, { "no changes yet", "created   2026-10-14T09:00", "modified  2026-10-14T09:00" })
  eq(child.api.nvim_win_get_config(0).relative, "editor") -- a float
  eq(child.api.nvim_win_get_cursor(0), { 1, #"Fix flaky test" - 1 }) -- on its last character
end

T["completion plugins are turned off in the form, not in the note"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  child.lua([[package.loaded.cmp = { setup = { buffer = function(opts)
    _G.cmp_off = { buf = vim.api.nvim_get_current_buf(), opts = opts }
  end } }]])
  child.cmd("edit " .. root .. "/tasks/fix.md")
  local note = child.api.nvim_get_current_buf()
  child.cmd("Logpose edit")
  local form = child.api.nvim_get_current_buf()
  eq(child.lua_get("_G.cmp_off"), { buf = form, opts = { enabled = false } })
  eq(form ~= note, true)
  eq(child.b.completion, false) -- blink.cmp
end

T["values are checked as you type, and the summary says what saving will do"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  set("status", "In progress")
  set("project", "Thesis Work")
  set("due", "fri")
  local d = drawn()
  eq(d.rows[2].eol, "") -- typed the column's name: nothing to add
  eq(d.rows[3].eol, "saved as thesis-work · new project")
  eq(d.rows[5].eol, "Fri 16 Oct · due tomorrow") -- worded as on the board
  eq(d.below[1], "saving will:")
  eq(d.below[2], "• move it to In progress, setting started (logged)")
  eq(d.below[3], "• project acme → thesis-work (logged)")
  eq(d.below[4], "• update due")
  set("status", "nope")
  set("due", "someday")
  d = drawn()
  eq(d.rows[2].eol, "✗ not a board column · <CR> to pick")
  H.contains(d.rows[5].eol, "✗ not a date")
  eq(d.below[1], "✗ fix 2 fields to save")
  -- saving refuses, says why and goes to the field; nothing is written
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("write")
  eq(child.bo.filetype, "logpose-edit")
  eq(last_msg(), "logpose: status: not a board column · <CR> to pick")
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
  H.contains(H.read(root .. "/tasks/fix.md"), "status: todo")
end

T["saving a task goes through the board's logic"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  set("title", "Fix the flaky checkout test")
  set("status", "In progress")
  set("project", "Thesis Work")
  set("tags", "ci, #flaky")
  set("due", "+3d")
  set("blocked", "waiting on Ana")
  child.cmd("write")
  -- the form stays open, showing what was written, ready for more changes
  eq(child.bo.filetype, "logpose-edit")
  eq(
    values(),
    { "Fix the flaky checkout test", "in-progress", "thesis-work", "ci, flaky", "2026-10-18", "waiting on Ana" }
  )
  eq(drawn().below[1], "no changes yet")
  child.type_keys("q")
  eq(child.bo.filetype, "markdown")
  local text = H.read(root .. "/tasks/fix.md")
  H.contains(text, 'title: "Fix the flaky checkout test"')
  H.contains(text, "status: in-progress")
  H.contains(text, "project: thesis-work")
  H.contains(text, "tags: [ci, flaky]")
  H.contains(text, "due: 2026-10-18")
  H.contains(text, "blocked: waiting on Ana")
  H.contains(text, "started: 2026-10-15")
  H.contains(text, "TODO → In progress")
  H.contains(text, "project: acme → thesis-work")
  H.contains(last_msg(), "saved")
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "status: in-progress")
end

T["saving keeps the form open; q warns about unsaved changes; :wq saves and closes"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  set("due", "fri")
  child.cmd("write")
  eq(child.bo.filetype, "logpose-edit")
  eq(last_msg(), "logpose: saved due")
  eq(values()[5], "2026-10-16") -- as written
  child.type_keys("u") -- nothing to undo: the form starts over after a save
  eq(values()[5], "2026-10-16")
  -- unsaved changes: the first q warns, the second discards
  set("blocked", "waiting on Ana")
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-edit")
  H.contains(last_msg(), "unsaved changes")
  child.type_keys("q")
  eq(child.bo.filetype, "markdown")
  H.contains(H.read(root .. "/tasks/fix.md"), "blocked:\n")
  -- :wq saves and closes
  child.cmd("Logpose edit")
  set("blocked", "waiting on Ana")
  child.cmd("wq")
  eq(child.bo.filetype, "markdown")
  H.contains(H.read(root .. "/tasks/fix.md"), "blocked: waiting on Ana")
end

T["a new task: set everything first; saving creates it, then the form edits it"] = function()
  child.lua(("require('logpose.edit').open_new(%q, { status = 'todo', project = 'acme' })"):format(root))
  eq(child.api.nvim_win_get_config(0).title[1][1], " New task ")
  eq(values(), { "", "todo", "acme", "", "", "", "" })
  local d = drawn()
  eq(d.rows[1].eol, "a short title") -- a hint, not an error, before you've typed
  eq(d.rows[7].label, "context")
  eq(d.below[2], "• create it in TODO, for acme")
  -- no title: saving says so and stays on it
  child.type_keys("<Esc>")
  set("due", "fri")
  child.cmd("write")
  H.contains(last_msg(), "give the task a title")
  eq(child.api.nvim_win_get_cursor(0)[1], 1)
  eq(vim.fn.glob(root .. "/tasks/*.md"), "")
  set("title", "Plan the migration")
  set("tags", "db, ops")
  eq(drawn().below, { "saving will:", "• create it in TODO, for acme", "• tagged db, ops", "• due tomorrow" })
  child.cmd("write")
  local path = root .. "/tasks/plan-the-migration.md"
  local text = H.read(path)
  H.contains(text, 'title: "Plan the migration"')
  H.contains(text, "status: todo")
  H.contains(text, "tags: [db, ops]")
  H.contains(text, "due: 2026-10-16")
  -- now it edits that task
  eq(child.api.nvim_win_get_config(0).title[1][1], " Edit task · Plan the migration ")
  eq(drawn().below[1], "no changes yet")
  set("blocked", "waiting on the DBA")
  child.cmd("write")
  H.contains(H.read(path), "blocked: waiting on the DBA")
  eq(child.lua_get("require('logpose.tasks').last"), path)
end

T["on the board, creating and then changing a new card are separate undo steps"] = function()
  child.cmd("Logpose board")
  child.type_keys("a", "Spike", "<Esc>")
  child.cmd("write") -- created
  set("project", "acme")
  child.cmd("write") -- changed
  child.type_keys("q")
  local path = root .. "/tasks/spike.md"
  H.contains(H.read(path), "project: acme")
  child.type_keys("u")
  eq(H.read(path):find("project: acme", 1, true), nil)
  child.type_keys("u")
  eq(H.read(path), nil)
end

T["dd clears a field, extra lines join the field above, u undoes both"] = function()
  H.write(root .. "/tasks/fix.md", TASK:gsub("due:\n", "due: 2026-10-20\n"))
  edit(root .. "/tasks/fix.md")
  on("tags")
  child.type_keys("dd")
  eq(values(), { "Fix flaky test", "todo", "acme", "", "2026-10-20", "" })
  child.type_keys("u")
  eq(values(), { "Fix flaky test", "todo", "acme", "ci", "2026-10-20", "" })
  -- the last field too
  on("blocked")
  child.type_keys("dd")
  eq(values(), { "Fix flaky test", "todo", "acme", "ci", "2026-10-20", "" })
  -- a pasted line joins the field above it
  on("title")
  child.fn.setreg("z", "and more\n", "l")
  child.type_keys('"zp')
  eq(values()[1], "Fix flaky test and more")
  eq(#values(), 6)
  child.cmd("write")
  local text = H.read(root .. "/tasks/fix.md")
  H.contains(text, 'title: "Fix flaky test and more"')
end

T["<C-a> and <C-x> cycle a field's values and step dates; <CR> picks one"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  H.write(root .. "/projects/thesis.md", '---\ntitle: "Master thesis"\nproject: thesis\n---\n')
  edit(root .. "/tasks/fix.md")
  on("status")
  child.type_keys("<C-a>")
  eq(values()[2], "in-progress")
  child.type_keys("2<C-x>")
  eq(values()[2], "backlog")
  on("due")
  child.type_keys("<C-a>") -- empty: today
  eq(values()[5], "2026-10-15")
  child.type_keys("<C-a>")
  eq(values()[5], "2026-10-16")
  child.type_keys("<C-x><C-x>")
  eq(values()[5], "2026-10-14")
  on("project")
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.picked = vim.tbl_map(opts.format_item, items)
    cb(items[3])
  end]])
  child.type_keys("<CR>")
  eq(child.lua_get("_G.picked"), { "—  no project", "acme", "thesis  Master thesis" })
  eq(values()[3], "thesis")
  -- a list field gets the item added
  on("tags")
  child.lua([[vim.ui.select = function(items, opts, cb)
    for _, it in ipairs(items) do if it.word == 'perf' then cb(it) end end
  end]])
  H.write(root .. "/tasks/other.md", "---\ntitle: o\nstatus: todo\ntags: [perf]\n---\n")
  child.lua("require('logpose.index').clear_cache()")
  child.type_keys("<CR>")
  eq(values()[4], "ci, perf")
  -- the title has nothing to pick: <CR> starts typing at its end
  on("title")
  child.type_keys("<CR>", "!", "<Esc>")
  eq(values()[1], "Fix flaky test!")
end

T["in insert mode, <CR> and <Tab> go to the next field"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  child.type_keys("A", "<CR>")
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
  eq(child.fn.mode(), "i")
  child.type_keys("<S-Tab>")
  eq(child.api.nvim_win_get_cursor(0)[1], 1)
  child.type_keys("<Tab>") -- nothing to complete in the title
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
  eq(#values(), 6) -- no new lines
  child.type_keys("<Esc>")
end

T["completion offers what fits each field"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  H.write(root .. "/tasks/other.md", "---\ntitle: other\nstatus: todo\nproject: thesis\ntags: [perf, docs]\n---\n")
  H.write(
    root .. "/meetings/x.md",
    '---\ntype: retro\ndate: 2026-10-01\ntitle: "R"\nattendees: [Ana, Luis]\n---\n## Notes\n'
  )
  H.write(root .. "/projects/thesis.md", '---\ntitle: "Master thesis"\nproject: thesis\n---\n')
  edit(root .. "/tasks/fix.md")
  local function words(key, text)
    set(key, text)
    on(key)
    child.type_keys("A") -- at the end of the value, in insert mode, as when typing
    local start = child.lua_get("require('logpose.edit').omnifunc(1, '')")
    local items = child.lua_get("require('logpose.edit').omnifunc(0, '')")
    child.type_keys("<Esc>")
    return start, vim.tbl_map(function(i)
      return i.word
    end, items)
  end
  local start, w = words("project", "th")
  eq({ start, w }, { 0, { "thesis" } })
  _, w = words("status", "in")
  eq(w, { "in-progress" })
  start, w = words("tags", "ci, p") -- the last item of a list, without the ones already there
  eq({ start, w }, { 4, { "perf" } })
  _, w = words("due", "")
  eq(w[1], "2026-10-15")
  eq(#w, 14)
  -- as you type: the menu opens, <Tab> picks, <CR> accepts
  on("project")
  child.type_keys("S", "th")
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<Tab>", "<CR>")
  eq(child.fn.pumvisible(), 0) -- accepting closes the menu; it doesn't open again
  eq(child.fn.mode(), "i")
  child.type_keys("<Esc>")
  eq(values()[3], "thesis")
  -- <CR> with nothing selected takes the best match: closed, same field, still typing
  child.type_keys("S", "th")
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<CR>")
  eq(child.fn.pumvisible(), 0)
  eq(child.fn.mode(), "i")
  eq(child.api.nvim_win_get_cursor(0)[1], 3)
  child.type_keys("<Esc>")
  eq(values()[3], "thesis")
  -- with nothing typed yet, <CR> closes the menu and goes to the next field, changing nothing
  child.type_keys("S")
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<CR>")
  eq(child.fn.pumvisible(), 0)
  eq(child.api.nvim_win_get_cursor(0)[1], 4)
  child.type_keys("<Esc>")
  eq(values()[3], "")
  set("project", "thesis")
  -- the same in a list: closed after accepting, open again for the next item
  set("tags", "ci")
  on("tags")
  child.type_keys("A", ", p")
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<Tab>", "<CR>")
  eq(child.fn.pumvisible(), 0)
  child.type_keys(", ")
  eq(child.fn.pumvisible(), 1) -- the next item: offered again, without the ones already there
  eq(child.fn.complete_info({ "items" }).items[1].word, "docs")
  child.type_keys("<C-e>", "<Esc>")
  eq(values()[4], "ci, perf, ")
  child.type_keys("q", "q") -- unsaved changes: the second q discards them
  edit(root .. "/meetings/x.md")
  _, w = words("attendees", "Ana, ")
  eq(w, { "Luis" })
end

T["moving a meeting to another project moves the note and fixes links"] = function()
  local old = root .. "/meetings/acme/2026-10-14 - retro.md"
  H.write(
    old,
    '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\nattendees: [Ana, Luis]\n'
      .. "series: acme/retro\n---\n## Notes\n"
  )
  H.write(
    root .. "/daily/daily-2026-10-14.md",
    "# 2026-10-14 daily notes\n\n## Meetings\n\n- acme: [[meetings/acme/2026-10-14 - retro|Retro]]\n"
  )
  edit(old)
  eq(child.api.nvim_win_get_config(0).title[1][1], " Edit meeting · Retro ") -- says what it edits
  set("project", "web")
  set("attendees", "Ana, Maria")
  local d = drawn()
  eq(d.below[2], "• move the note to meetings/web/, fixing 1 link to it")
  eq(d.below[3], "• update attendees")
  eq(d.rows[5].eol, "new: Maria") -- nobody by that name yet: a new person, or a typo
  -- shown, not edited
  assert(table.concat(d.below, "\n"):find("series%s+acme/retro"), "series shown below")
  child.cmd("write")
  child.type_keys("q")
  local new = root .. "/meetings/web/2026-10-14 - retro.md"
  eq(vim.fn.filereadable(old), 0)
  eq(vim.fn.isdirectory(root .. "/meetings/acme"), 0)
  local text = H.read(new)
  H.contains(text, "project: web")
  H.contains(text, "series: web/retro")
  H.contains(text, "attendees: [Ana, Maria]")
  eq(
    H.read(root .. "/daily/daily-2026-10-14.md"),
    "# 2026-10-14 daily notes\n\n## Meetings\n\n- web: [[meetings/web/2026-10-14 - retro|Retro]]\n"
  )
  eq(text:match("\n\n$"), nil) -- no blank line added at the end
  eq(child.api.nvim_buf_get_name(0), new)
end

T["+ adds a field and ? shows the keys"] = function()
  H.write(root .. "/notes/q.md", '---\ntitle: "Queue design"\n---\n## Notes\n')
  edit(root .. "/notes/q.md")
  child.lua([[vim.ui.input = function(_, cb) cb('status') end]])
  child.type_keys("+")
  eq(drawn().rows[4].label, "status")
  eq(child.fn.mode(), "i")
  child.type_keys("draft", "<Esc>")
  child.lua([[vim.ui.input = function(_, cb) cb('created') end]])
  child.type_keys("+")
  H.contains(last_msg(), "kept by logpose")
  child.type_keys("?")
  H.contains(table.concat(drawn().below, "\n"), "<C-a> <C-x>")
  child.cmd("write")
  H.contains(H.read(root .. "/notes/q.md"), "status: draft")
end

T["e on the board edits the card, and u undoes it"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  child.cmd("Logpose board")
  child.type_keys("l", "e") -- the card is in TODO
  eq(child.bo.filetype, "logpose-edit")
  set("project", "thesis")
  child.cmd("write")
  set("status", "in-progress")
  child.cmd("write") -- a second change, saved separately
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-board")
  H.contains(H.read(root .. "/tasks/fix.md"), "project: thesis")
  H.contains(H.read(root .. "/tasks/fix.md"), "status: in-progress")
  child.type_keys("u") -- each save is its own undo step
  H.contains(H.read(root .. "/tasks/fix.md"), "status: todo")
  H.contains(H.read(root .. "/tasks/fix.md"), "project: thesis")
  child.type_keys("u")
  H.contains(H.read(root .. "/tasks/fix.md"), "project: acme")
end

T["e in the projects manager edits the project page"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  child.cmd("Logpose projects")
  child.fn.search("acme")
  child.type_keys("e")
  eq(child.bo.filetype, "logpose-edit")
  eq(drawn().rows[3].label, "paths")
  set("title", "Acme API")
  set("description", "Payments")
  child.cmd("write")
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-projects")
  local page = H.read(root .. "/projects/acme.md")
  H.contains(page, 'title: "Acme API"')
  H.contains(page, "description: Payments")
  H.contains(table.concat(values(), "\n"), "Acme API")
  -- the project's own name isn't offered: renaming belongs to R
  child.type_keys("e")
  eq(
    vim.tbl_contains(
      vim.tbl_map(function(r)
        return r.label
      end, drawn().rows),
      "project"
    ),
    true
  )
  set("project", "other")
  local msg
  for _, r in pairs(drawn().rows) do
    if r.label == "project" then
      msg = r.eol
    end
  end
  eq(msg, "✗ rename a project with R in :Logpose projects (it updates every note)")
end

T[":Logpose edit outside the journal says so"] = function()
  child.cmd("enew")
  child.cmd("Logpose edit")
  H.contains(last_msg(), "works on a journal note")
  child.cmd("Logpose edit last")
  H.contains(last_msg(), "nothing captured yet")
end

T[":Logpose edit on quickfix lines edits those tasks together"] = function()
  H.write(root .. "/tasks/a.md", TASK:gsub("Fix flaky test", "A"))
  H.write(root .. "/tasks/b.md", TASK:gsub("Fix flaky test", "B"):gsub("project: acme", "project: thesis"))
  child.lua(
    ([[vim.fn.setqflist({ { filename = %q, lnum = 1, text = 'A' }, { filename = %q, lnum = 1, text = 'B' } })]]):format(
      root .. "/tasks/a.md",
      root .. "/tasks/b.md"
    )
  )
  child.cmd("copen")
  child.cmd("1,2Logpose edit")
  eq(child.bo.filetype, "logpose-edit")
  eq(values(), { "todo", "", "ci", "", "" }) -- project differs: left empty, meaning "as is"
  H.contains(drawn().rows[2].eol, "unchanged")
  set("project", "none")
  set("tags", "-ci +review")
  set("due", "fri")
  local d = drawn()
  eq(d.rows[2].eol, "clears it")
  eq(d.rows[3].eol, "adds review · removes ci")
  eq(d.below[2], "• remove the project (logged)")
  child.cmd("write")
  for _, name in ipairs({ "a", "b" }) do
    local text = H.read(root .. "/tasks/" .. name .. ".md")
    H.contains(text, "project:\n")
    H.contains(text, "tags: [review]")
    H.contains(text, "due: 2026-10-16")
    H.contains(text, "status: todo")
  end
  eq(last_msg(), "logpose: saved due, project, tags on 2 of 2 tasks")
  eq(values(), { "todo", "", "review", "2026-10-16", "" }) -- read back: now shared
end

return T

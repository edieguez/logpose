local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(
    ("require('logpose').setup(vim.tbl_extend('force', { root = %q, picker = 'select' }, %s))"):format(
      root,
      extra or "{}"
    )
  )
end

--- A task file with these frontmatter lines and a log.
local function task(name, fm, log)
  local lines = { "---", ('title: "%s"'):format(fm.title or name) }
  for _, k in ipairs({ "status", "project", "due", "blocked", "cancelled", "created", "started", "done" }) do
    if fm[k] then
      table.insert(lines, k .. ": " .. fm[k])
    end
  end
  vim.list_extend(lines, { "---", "## Log", "" })
  vim.list_extend(lines, log or { "- 2026-10-10 09:00: created in Backlog" })
  H.write(root .. "/tasks/" .. name .. ".md", table.concat(lines, "\n") .. "\n")
  return root .. "/tasks/" .. name .. ".md"
end

local function fm(path)
  return child.lua_get(("require('logpose.index').frontmatter(vim.fn.readfile(%q))"):format(path))
end

local function screen()
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.o.columns, child.o.lines = 160, 40
      setup()
      H.freeze(child, 2026, 10, 15, 9, 30) -- Thursday; the week started Monday 10-12
      task("spike", { status = "in-progress", project = "acme", blocked = "waiting on ana", started = "2026-10-12" }, {
        "- 2026-10-10 09:00: created in Backlog",
        "- 2026-10-12 09:00: Backlog → In progress",
      })
      task("docs", { status = "todo", project = "acme", due = "2026-10-15" })
      task("shipped", { status = "done", project = "acme", done = "2026-10-14" })
    end,
    post_once = child.stop,
  },
})

T["a task with cancelled: but no status: still counts as cancelled"] = function()
  local path = task("legacy", { project = "acme", cancelled = "old reason" }, {
    "- 2026-10-10 09:00: created in Backlog",
    "- 2026-10-14 09:00: Backlog → Cancelled",
  })
  local t = child.lua_get(("require('logpose.taskfile').parse(%q, vim.fn.readfile(%q), %q)"):format(path, path, root))
  eq({ t.status, t.cancelled, t.since }, { "cancelled", "old reason", "2026-10-14" })
  child.cmd("Logpose board")
  H.contains(screen(), "✗ legacy")
  H.contains(screen(), "cancelled: old reason")
  eq(
    child.lua_get(
      ("#require('logpose.query').filter(require('logpose.index').build(%q), require('logpose.query').parse({ 'cancelled' }))"):format(
        root
      )
    ),
    1
  )
end

T["cancelling: status and reason, blocked cleared, started kept, logged; moving it reopens it"] = function()
  local path = root .. "/tasks/spike.md"
  local cancel = function(reason)
    return child.lua_get(("require('logpose.taskfile').set_cancelled(%q, %s)"):format(path, reason))
  end
  eq(cancel("'duplicate of the queue work'"), true)
  local f = fm(path)
  eq({ f.status, f.cancelled, f.blocked, f.started }, { "cancelled", "duplicate of the queue work", "", "2026-10-12" })
  local text = H.read(path)
  H.contains(
    text,
    "- 2026-10-15 09:30: In progress → Cancelled\n- 2026-10-15 09:30: cancelled: duplicate of the queue work"
  )
  eq(cancel("'duplicate of the queue work'"), false) -- the same: nothing to do
  eq(cancel("false"), true) -- no reason after all
  eq(fm(path).cancelled, "yes")
  -- it left In progress: reopening goes back there, and clears the reason
  eq(child.lua_get(("require('logpose.taskfile').reopen_column(%q)"):format(path)), "in-progress")
  child.lua(("require('logpose.taskfile').set_status(%q, 'in-progress')"):format(path))
  f = fm(path)
  eq(f.status, "in-progress")
  eq(f.cancelled, nil)
  H.contains(H.read(path), "Cancelled → In progress")
  -- closed and cancelled
  eq(
    child.lua_get(
      "{ require('logpose.taskfile').is_closed('done'), require('logpose.taskfile').is_closed('cancelled'), require('logpose.taskfile').is_closed('todo'), require('logpose.taskfile').label('cancelled') }"
    ),
    { true, true, false, "Cancelled" }
  )
end

T["a new task leaves cancelled out of its frontmatter"] = function()
  local path = child.lua_get(("require('logpose.taskfile').create(%q, { title = 'Fresh' })"):format(root))
  eq(H.read(path):find("cancelled", 1, true), nil)
end

T["the board: X cancels with a reason; the card sits in Done, struck through; X again reopens it"] = function()
  child.cmd("Logpose board")
  child.type_keys("l", "l") -- In progress: the spike
  child.lua("vim.ui.input = function(o, cb) _G.prompt = o.prompt; cb('duplicate') end")
  child.type_keys("X")
  eq(child.lua_get("_G.prompt"), "Cancel it: why? (Enter: no reason) ")
  eq(fm(root .. "/tasks/spike.md").status, "cancelled")
  local s = screen()
  H.contains(s, "✗ spike")
  H.contains(s, "duplicate")
  eq(s:find("waiting on ana", 1, true), nil) -- not blocked any more
  -- in Done, after the finished ones, struck through
  local b = child.lua_get([[(function()
    local b = require('logpose.board').boards[vim.fn.bufnr('logpose://board')]
    local done = b.columns[#b.columns]
    return vim.tbl_map(function(it) return it.text end, done.cards)
  end)()]])
  eq(b, { "shipped", "spike" })
  local struck = child.lua_get([[(function()
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      if m[4].hl_group == 'LogposeBoardCancelled' then return true end
    end
    return false
  end)()]])
  eq(struck, true)
  eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'LogposeBoardCancelled' }).strikethrough"), true)
  -- u undoes it
  child.type_keys("u")
  eq(fm(root .. "/tasks/spike.md").status, "in-progress")
  child.type_keys("<C-r>")
  eq(fm(root .. "/tasks/spike.md").status, "cancelled")
  -- X on the cancelled card: back to the column it left
  local done_col = child.lua_get("#require('logpose.board').boards[vim.fn.bufnr('logpose://board')].columns")
  child.lua(
    ("require('logpose.board').boards[vim.fn.bufnr('logpose://board')].focus = { col = %d, row = 2 }"):format(done_col)
  )
  child.type_keys("X")
  eq(fm(root .. "/tasks/spike.md").status, "in-progress")
end

T["the board: marked cards are cancelled together, one undo step; H takes a cancelled card out of Done"] = function()
  child.cmd("Logpose board")
  child.type_keys("l", "v", "l", "v") -- docs (TODO), spike (In progress)
  child.lua("vim.ui.input = function(o, cb) _G.prompt = o.prompt; cb('') end")
  child.type_keys("X")
  eq(child.lua_get("_G.prompt"), "Cancel 2 cards: why? (Enter: no reason) ")
  eq({ fm(root .. "/tasks/docs.md").cancelled, fm(root .. "/tasks/spike.md").cancelled }, { "yes", "yes" })
  H.contains(last_msg(), "cancelled 2 of 2 marked cards")
  child.type_keys("u")
  eq({ fm(root .. "/tasks/docs.md").status, fm(root .. "/tasks/spike.md").status }, { "todo", "in-progress" })
  -- <Esc> at the question: nothing happens
  child.type_keys("V")
  child.lua("vim.ui.input = function(o, cb) cb(nil) end")
  child.type_keys("X")
  eq(fm(root .. "/tasks/spike.md").status, "in-progress")
  -- H on a cancelled card in Done reopens it into the column before Done
  child.lua(("require('logpose.taskfile').set_cancelled(%q)"):format(root .. "/tasks/docs.md"))
  child.type_keys("r")
  local done_col = child.lua_get("#require('logpose.board').boards[vim.fn.bufnr('logpose://board')].columns")
  child.lua(
    ("require('logpose.board').boards[vim.fn.bufnr('logpose://board')].focus = { col = %d, row = 2 }"):format(done_col)
  )
  child.type_keys("H")
  eq(fm(root .. "/tasks/docs.md").status, "follow-up")
end

T["the board's Done shows what was cancelled in the window only"] = function()
  task("old", { status = "cancelled", cancelled = "yes" }, {
    "- 2026-09-01 09:00: created in Backlog",
    "- 2026-09-02 09:00: Backlog → Cancelled",
  })
  task("recent", { status = "cancelled", cancelled = "yes" }, {
    "- 2026-10-10 09:00: created in Backlog",
    "- 2026-10-13 09:00: Backlog → Cancelled",
  })
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, "✗ recent")
  eq(s:find("old", 1, true), nil)
end

T[":Logpose cancel in a task file; elsewhere it says so"] = function()
  child.cmd("edit " .. root .. "/tasks/docs.md")
  child.cmd("Logpose cancel no longer needed")
  local f = fm(root .. "/tasks/docs.md")
  eq({ f.status, f.cancelled }, { "cancelled", "no longer needed" })
  H.contains(last_msg(), "cancelled: no longer needed")
  child.cmd("Logpose cancel")
  H.contains(last_msg(), "cancelled already")
  child.cmd("enew")
  child.cmd("Logpose cancel")
  H.contains(last_msg(), "works in a task file")
end

T["the form: status offers Cancelled after the columns; saving cancels; the reason can change"] = function()
  child.cmd("edit " .. root .. "/tasks/docs.md")
  child.cmd("Logpose edit")
  local words = child.lua_get(
    ("vim.tbl_map(function(i) return i.word end, require('logpose.edit.form').candidates(%q, 'task', 'status', '', {}))"):format(
      root
    )
  )
  eq(words[#words], "cancelled")
  child.api.nvim_buf_set_lines(0, 1, 2, false, { "Cancelled" })
  child.lua("require('logpose.edit.form').render(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])")
  local below = child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      for _, vl in ipairs(m[4].virt_lines or {}) do
        table.insert(out, vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, vl))))
      end
    end
    return table.concat(out, "\n")
  end)()]])
  H.contains(below, "cancel it: closed, not done (logged)")
  child.cmd("write")
  eq(fm(root .. "/tasks/docs.md").status, "cancelled")
  -- the form now shows the reason, which can change
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  for i, l in ipairs(lines) do
    if l == "yes" then
      row = i
    end
  end
  child.api.nvim_buf_set_lines(0, row - 1, row, false, { "superseded" })
  child.cmd("write")
  eq(fm(root .. "/tasks/docs.md").cancelled, "superseded")
  H.contains(H.read(root .. "/tasks/docs.md"), "cancelled: superseded")
  child.type_keys("q")
  -- a new task starts in a column
  child.lua(("require('logpose.edit').open_new(%q, { status = 'cancelled' })"):format(root))
  local d = child.lua_get([[(function()
    local f = require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()]
    return f.result.errors.status
  end)()]])
  eq(d, "a new task starts in a column")
end

T["filters: open and done leave cancelled tasks out; cancelled and status:cancelled find them"] = function()
  child.lua(("require('logpose.taskfile').set_cancelled(%q, 'nope')"):format(root .. "/tasks/docs.md"))
  local q = function(args)
    return child.lua_get(
      ([[vim.tbl_map(function(it) return it.text end,
      vim.tbl_filter(function(it) return it.kind == 'task' end,
        require('logpose.query').filter(require('logpose.index').build(%q), require('logpose.query').parse(%s))))]]):format(
        root,
        args
      )
    )
  end
  eq(q("{ 'open' }"), { "spike" })
  eq(q("{ 'done' }"), { "shipped" })
  eq(q("{ 'cancelled' }"), { "docs" })
  eq(q("{ 'status:cancelled' }"), { "docs" })
end

T["closed but not done: off the statusline, today, the status's Today, and the projects' counts"] = function()
  -- docs is due today: it's in Today and in today's due list until it's cancelled
  child.lua(("require('logpose.taskfile').set_cancelled(%q)"):format(root .. "/tasks/docs.md"))
  child.lua(("require('logpose.taskfile').set_cancelled(%q)"):format(root .. "/tasks/spike.md"))
  local today = child.lua_get(
    ("vim.tbl_map(function(e) return e.label end, require('logpose.notes.status').collect(%q).today)"):format(root)
  )
  eq(today, {})
  local blockers = child.lua_get(("#require('logpose.notes.status').collect(%q).blockers"):format(root))
  eq(blockers, 0)
  eq(child.lua_get(("require('logpose.statusline').get({ project = false, period = false })"):format()), "")
  local acme = child.lua_get(([[(function()
    for _, e in ipairs(require('logpose.projects.summary').stats(%q)) do
      if e.name == 'acme' then return { e.open, e.done, e.cancelled, e.blocked } end
    end
  end)()]]):format(root))
  eq(acme, { 0, 1, 2, 0 })
end

T["archive: cancelled tasks go with the done ones, by the day they were cancelled"] = function()
  task("dropped", { status = "cancelled", cancelled = "yes" }, {
    "- 2026-09-01 09:00: created in Backlog",
    "- 2026-09-30 09:00: Backlog → Cancelled",
  })
  child.cmd("Logpose archive!")
  eq(vim.fn.filereadable(root .. "/tasks/archive/week-2026-09-28/dropped.md"), 1)
  eq(vim.fn.filereadable(root .. "/tasks/spike.md"), 1) -- open: stays
end

T["config: the cancelled status can't be a column"] = function()
  local ok, err =
    pcall(child.lua, ("require('logpose').setup({ root = %q, board = { cancelled = 'done' } })"):format(root))
  eq(ok, false)
  H.contains(tostring(err), '`board.cancelled` = "done" is a column')
end

T["C29"] = MiniTest.new_set()

T["C29"]["a to-do made into a task: [-] when it's cancelled, back to [ ] or [x] when it's reopened or done"] = function()
  local retro = root .. "/meetings/acme/2026-10-14 - retro.md"
  local daily = root .. "/daily/daily-2026-10-15.md"
  H.write(
    retro,
    '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\n---\n- [ ] fix CI @ana\n  → [[tasks/docs|task]]\n'
  )
  H.write(daily, "# d\n\n- [ ] fix CI @ana\n  → [[tasks/docs|task]]\n")
  local task = root .. "/tasks/docs.md"
  child.lua(("require('logpose.taskfile').set_cancelled(%q, 'not needed')"):format(task))
  H.contains(H.read(retro), "- [-] fix CI @ana\n  → [[tasks/docs|task]]")
  H.contains(H.read(daily), "- [-] fix CI @ana")
  H.contains(last_msg(), "marked [-] (cancelled) its to-do in")
  -- not an action item any more
  child.cmd("Logpose actions")
  eq(#child.fn.getqflist(), 0)
  child.cmd("cclose")
  -- reopened: an open to-do again
  child.lua(("require('logpose.taskfile').set_status(%q, 'todo')"):format(task))
  H.contains(H.read(retro), "- [ ] fix CI @ana")
  -- done, then cancelled: checked, then [-]
  child.lua(("require('logpose.taskfile').set_status(%q, 'done')"):format(task))
  H.contains(H.read(retro), "- [x] fix CI @ana")
  child.lua(("require('logpose.taskfile').set_cancelled(%q)"):format(task))
  H.contains(H.read(retro), "- [-] fix CI @ana")
  -- a note with unsaved changes is changed in its buffer
  child.lua(("require('logpose.taskfile').set_status(%q, 'todo')"):format(task))
  child.cmd("edit " .. daily)
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# day" })
  child.lua(("require('logpose.taskfile').set_cancelled(%q)"):format(task))
  eq(child.api.nvim_buf_get_lines(0, 2, 3, false), { "- [-] fix CI @ana" })
  eq(child.bo.modified, true)
end

T["C29"]["the board's undo puts the to-do back too"] = function()
  local retro = root .. "/meetings/acme/2026-10-14 - retro.md"
  H.write(
    retro,
    '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\n---\n- [ ] write the docs\n  → [[tasks/docs|task]]\n'
  )
  child.cmd("Logpose board")
  child.type_keys("l") -- TODO: docs
  child.lua("vim.ui.input = function(o, cb) cb('') end")
  child.type_keys("X")
  H.contains(H.read(retro), "- [-] write the docs")
  child.type_keys("u")
  H.contains(H.read(retro), "- [ ] write the docs")
  child.type_keys("<C-r>")
  H.contains(H.read(retro), "- [-] write the docs")
end

T["C29"]["the status's Yesterday says a task was cancelled; Today and Blockers leave it out"] = function()
  task("dropped", { status = "cancelled", cancelled = "superseded", project = "acme" }, {
    "- 2026-10-10 09:00: created in Backlog",
    "- 2026-10-14 11:00: TODO → Cancelled",
    "- 2026-10-14 11:00: cancelled: superseded",
  })
  local s = child.lua_get(([[(function()
    local s = require('logpose.notes.status').collect(%q)
    local function t(list) return vim.tbl_map(function(e) return e.label .. ' (' .. e.note .. ')' end, list) end
    return { yesterday = t(s.yesterday), today = t(s.today), blockers = t(s.blockers) }
  end)()]]):format(root))
  H.contains(table.concat(s.yesterday, "\n"), "dropped (TODO → Cancelled)")
  eq(table.concat(s.today, "\n"):find("dropped", 1, true), nil)
  eq(table.concat(s.blockers, "\n"):find("dropped", 1, true), nil)
end

T["C29"]["the report lists what was cancelled in the period, with why, apart from what was done"] = function()
  task("dropped", { status = "cancelled", cancelled = "superseded", project = "acme" }, {
    "- 2026-10-10 09:00: created in Backlog",
    "- 2026-10-13 11:00: TODO → Cancelled",
  })
  task("quiet", { status = "cancelled", cancelled = "yes" }, {
    "- 2026-10-10 09:00: created in Backlog",
    "- 2026-10-14 11:00: Backlog → Cancelled",
  })
  child.cmd("Logpose report week")
  local r = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(r, "## Done tasks (1)\n\n### 2026-10-14\n\n- shipped (")
  H.contains(
    r,
    "## Cancelled tasks (2)\n\n- 2026-10-13 dropped: superseded ([[tasks/dropped|dropped]])  @acme\n"
      .. "- 2026-10-14 quiet ([[tasks/quiet|quiet]])"
  )
  child.cmd("close")
  child.cmd("Logpose report week project:acme")
  r = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(r, "## Cancelled tasks (1)")
end

T["C29"]["a 1:1's updates: a task they care about that was cancelled since the last one"] = function()
  H.write(root .. "/people/ana.md", '---\nname: "Ana"\n---\n')
  H.write(
    root .. "/meetings/2026-10-01 - 1-1-ana.md",
    '---\ntype: 1on1\ndate: 2026-10-01\ntitle: "1:1 Ana"\nwith: Ana\n---\n'
  )
  local path = task("pricing", { status = "cancelled", cancelled = "no budget" }, {
    "- 2026-09-20 09:00: created in TODO",
    "- 2026-10-08 09:00: TODO → Cancelled",
  })
  H.write(path, H.read(path):gsub("status: cancelled", "status: cancelled\nstakeholders: [Ana]"))
  local note = child.lua_get(([[(function()
    local m = require("logpose.notes.meeting")
    local n = m.build(%q, "1on1", "Ana", "2026-10-15")
    m.write(%q, n, true)
    return n
  end)()]]):format(root, root))
  H.contains(H.read(note.path), "## Updates\n\n- [[tasks/pricing|pricing]] — TODO → Cancelled\n")
end

return T

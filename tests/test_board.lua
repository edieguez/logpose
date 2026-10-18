local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local function task(name, fields, body)
  local lines = { "---", ('title: "%s"'):format(fields.title or name) }
  for _, k in ipairs({ "status", "project", "tags", "due", "blocked", "created", "started", "done", "order" }) do
    if fields[k] then
      table.insert(lines, k .. ": " .. fields[k])
    end
  end
  table.insert(lines, "---")
  table.insert(lines, "# " .. (fields.title or name))
  table.insert(lines, body or "")
  H.write(root .. "/tasks/" .. name .. ".md", table.concat(lines, "\n") .. "\n")
  return root .. "/tasks/" .. name .. ".md"
end

local function status(path)
  return child.lua_get(
    ("require('logpose.taskfile').parse(%q, vim.fn.readfile(%q), %q).status"):format(path, path, root)
  )
end

--- The board's title, shown in the window's top bar (winbar).
local function title()
  return child.lua_get("require('logpose.board').boards[vim.fn.bufnr('logpose://board')].title")
end

local function screen()
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.o.columns, child.o.lines = 160, 40
      setup()
      H.freeze(child, 2026, 10, 15) -- Thursday; the week started Monday 10-12
      task("fix-flaky", {
        title = "Fix flaky test",
        status = "todo",
        project = "acme",
        tags = "[perf]",
        due = "2026-10-14",
        created = "2026-10-10",
      })
      task("read-paper", { title = "Read paper", status = "backlog", project = "thesis", created = "2026-10-11" })
      task("queue", {
        title = "Queue design",
        status = "in-progress",
        project = "acme",
        blocked = "waiting on ana",
        created = "2026-10-09",
        started = "2026-10-12",
      })
      task("shipped", { title = "Ship it", status = "done", project = "acme", done = "2026-10-13" })
      task("old", { title = "Old work", status = "done", project = "acme", done = "2026-10-02" })
    end,
    post_once = child.stop,
  },
})

T["shows columns side by side with cards, counts and meta"] = function()
  child.cmd("Logpose board")
  local s = screen()
  eq(title(), "Board · all projects")
  H.contains(child.wo.winbar, "%#LogposeBoardTitle# Board")
  local headers = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  for _, h in ipairs({ "● Backlog (1)", "● TODO (1)", "● In progress (1/3)", "● Follow-up (0)", "● Done (1)" }) do
    H.contains(headers, h) -- "Old work" finished last week: not in Done
  end
  H.contains(s, "⊘ waiting on ana")
  H.contains(s, "◆ acme · overdue 1d  #perf ") -- details: project, when it's due, tag chips
  H.contains(s, "✓ Ship it") -- done
  H.contains(s, "╭─") -- cards are boxes
  H.contains(s, "┏━") -- the focused one has a heavy border
  H.contains(s, "┃ Queue design") -- a blocked card's left edge
  eq(s:find("Old work", 1, true), nil)
  -- no trailing whitespace anywhere, the last column included
  for _, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    eq(l:match("%s$"), nil)
  end
  eq(child.bo.filetype, "logpose-board")
  eq(child.bo.modifiable, false)
end

T["stacks the columns when the window is narrow"] = function()
  child.o.columns = 80
  child.cmd("Logpose board")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[3]:find("│", 1, true), nil)
  H.contains(screen(), " TODO (1)")
  -- focus and moves still work column by column
  child.type_keys("l")
  child.type_keys("L")
  eq(status(root .. "/tasks/fix-flaky.md"), "in-progress")
end

T["h/l/j/k move the focus; H/L, digits and x move the card"] = function()
  child.cmd("Logpose board")
  local flaky = root .. "/tasks/fix-flaky.md"
  child.type_keys("l") -- TODO column: Fix flaky test
  child.type_keys("L")
  eq(status(flaky), "in-progress")
  -- focus follows the card into In progress (sorted after Queue design: due first? no, order: due then created)
  child.type_keys("L")
  eq(status(flaky), "follow-up")
  child.type_keys("H")
  eq(status(flaky), "in-progress")
  child.type_keys("1")
  eq(status(flaky), "backlog")
  child.type_keys("x")
  eq(status(flaky), "done")
  H.contains(screen(), "Done (2)")
  local content = H.read(flaky)
  H.contains(content, "done: 2026-10-15")
  H.contains(content, "started: 2026-10-15")
  H.contains(content, "Follow-up → In progress")
end

T["b blocks with a reason and unblocks"] = function()
  child.cmd("Logpose board")
  child.lua([[vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('needs review') end]])
  child.type_keys("lb")
  eq(child.lua_get("_G.prompt"), "Blocked by: ")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "blocked: needs review")
  H.contains(screen(), "⊘ needs review")
  child.type_keys("b")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "blocked:\n")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "unblocked")
end

T["a adds a card to the focused column with the active project"] = function()
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(child.fn.getcwd()))
  child.cmd("Logpose board")
  child.lua([[vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('New idea') end]])
  child.type_keys("ll")
  child.type_keys("a")
  eq(child.lua_get("_G.prompt"), "New task in In progress → acme (this board): ")
  local content = H.read(root .. "/tasks/new-idea.md")
  H.contains(content, "status: in-progress")
  H.contains(content, "project: acme")
  H.contains(screen(), "New idea")
  -- the text is parsed like a capture: tags, due date, another project
  child.lua([[vim.ui.input = function(opts, cb) cb('Draft intro #writing due:fri +thesis') end]])
  child.type_keys("a")
  content = H.read(root .. "/tasks/draft-intro.md")
  H.contains(content, "project: thesis")
  H.contains(content, "tags: [writing]")
  H.contains(content, "due: 2026-10-16")
end

T["a in rows per project adds the card to the row you're in"] = function()
  child.cmd("Logpose board")
  child.type_keys("s")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find("Read paper", 1, true) then
      child.api.nvim_win_set_cursor(0, { i, (l:find("Read paper", 1, true)) })
    end
  end
  child.lua([[vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb('Outline') end]])
  child.type_keys("a")
  H.contains(child.lua_get("_G.prompt"), "→ thesis (this row): ")
  H.contains(H.read(root .. "/tasks/outline.md"), "project: thesis")
end

T["the active project scopes the board; p shows all"] = function()
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(child.fn.getcwd()))
  child.cmd("Logpose board")
  eq(title(), "Board · acme")
  eq(screen():find("Read paper", 1, true), nil)
  child.type_keys("p")
  eq(title(), "Board · all projects")
  H.contains(screen(), "Read paper")
end

T["filters from the command line and /"] = function()
  child.cmd("Logpose board #perf")
  eq(title(), "Board · all projects · #perf")
  eq(screen():find("Read paper", 1, true), nil)
  H.contains(screen(), "Fix flaky test")
  child.lua([[vim.ui.input = function(opts, cb) _G.default = opts.default; cb('blocked') end]])
  child.type_keys("/")
  eq(child.lua_get("_G.default"), "#perf")
  H.contains(screen(), "Queue design")
  eq(screen():find("Fix flaky test", 1, true), nil)
end

T["<C-j>/<C-k> reorder cards within a column"] = function()
  task("a-first", { title = "Alpha", status = "todo", created = "2026-10-01" })
  child.cmd("Logpose board")
  child.type_keys("l") -- TODO: Fix flaky (due) then Alpha
  local s = screen()
  assert(s:find("Fix flaky test", 1, true) < s:find("Alpha", 1, true))
  child.type_keys("<C-j>")
  s = screen()
  assert(s:find("Alpha", 1, true) < s:find("Fix flaky test", 1, true))
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "order: 2")
  H.contains(H.read(root .. "/tasks/a-first.md"), "order: 1")
  -- moving to another column drops the order
  child.type_keys("L")
  eq(H.read(root .. "/tasks/fix-flaky.md"):find("order:", 1, true), nil)
end

T["the cursor selects a card; <CR> opens it and the board refreshes on return"] = function()
  child.cmd("Logpose board")
  -- put the cursor on the In progress card and let CursorMoved pick it up
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  for i, l in ipairs(lines) do
    if l:find("Queue design", 1, true) then
      row = i
    end
  end
  local col = lines[row]:find("Queue design", 1, true)
  child.api.nvim_win_set_cursor(0, { row, col })
  child.cmd("doautocmd CursorMoved")
  child.type_keys("<CR>")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/queue.md")
  child.lua(("require('logpose.taskfile').set_status(%q, 'follow-up')"):format(root .. "/tasks/queue.md"))
  child.cmd("buffer logpose://board")
  H.contains(screen(), "In progress (0/3)")
  H.contains(screen(), "Follow-up (1)")
end

T["q closes the board and returns to the previous buffer"] = function()
  child.cmd("edit " .. root .. "/tasks/read-paper.md")
  child.cmd("Logpose board")
  child.type_keys("q")
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/read-paper.md")
  eq(child.fn.bufnr("logpose://board"), -1)
end

T["done_window can be a number of days"] = function()
  setup("{ board = { done_window = 30 } }")
  child.cmd("Logpose board")
  H.contains(screen(), "Done (2)")
  H.contains(screen(), "Old work")
end

T["triage opens the board on Backlog; ? shows help"] = function()
  child.cmd("Logpose triage")
  eq(child.bo.filetype, "logpose-board")
  child.type_keys("x")
  eq(status(root .. "/tasks/read-paper.md"), "done")
  child.type_keys("?")
  H.contains(child.notifications()[#child.notifications()].msg, "H / L  < >   move the card left / right")
end

T["custom columns"] = function()
  setup(
    [[{ board = { columns = { { key = 'todo', label = 'To do' }, { key = 'doing' }, { key = 'done', label = 'Done' } }, start = 'doing' }, tasks = { capture_status = 'todo', promote_status = 'todo' } }]]
  )
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, " To do (3)") -- statuses without a column show in the capture column
  H.contains(s, "● doing (0)")
  child.type_keys("L")
  eq(status(root .. "/tasks/fix-flaky.md"), "doing")
end

T["standup lists board work; report and health count it"] = function()
  task("yesterday", { title = "Finished yesterday", status = "done", project = "acme", done = "2026-10-14" })
  child.cmd("Logpose standup")
  local s = screen()
  H.contains(s, "## Yesterday\n\n### acme\n\n- [x] Finished yesterday #acme")
  H.contains(s, "## Today\n\n### acme\n\n- [ ] Queue design #acme")
  H.contains(s, "## Blockers\n\n### acme\n\n- Queue design: waiting on ana #acme")

  local report = table.concat(
    child.lua_get(
      ("require('logpose.report').build(%q, require('logpose.period').of('2026-10-15'), {}, '2026-10-15', %q)"):format(
        root,
        root .. "/reports/x.md"
      )
    ),
    "\n"
  )
  H.contains(report, "- Ship it ([[tasks/shipped|Ship it]])  @acme")
  H.contains(
    report,
    "### Blocked tasks (1)\n\n- [In progress] Queue design: waiting on ana ([[tasks/queue|Queue design]])"
  )
  H.contains(report, "### In progress for more than 14 days (0)")

  child.cmd("checkhealth logpose")
  H.contains(screen(), "Task files: Backlog 1 · TODO 1 · In progress 1 · Follow-up 0 · Done 3")
end

T["archive moves done tasks from earlier periods"] = function()
  child.lua(
    [[vim.ui.select = function(items, opts, cb) _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false); cb('Archive') end]]
  )
  child.cmd("Logpose archive")
  H.contains(
    table.concat(child.lua_get("_G.preview"), "\n"),
    "Done tasks\n  → tasks/archive/week-2026-09-28/: old.md"
  )
  eq(H.read(root .. "/tasks/old.md"), nil)
  H.contains(H.read(root .. "/tasks/archive/week-2026-09-28/old.md"), "Old work")
  H.contains(child.notifications()[1].msg, "archived 1 done task")
  -- still counted in a report for that week
  local report = table.concat(
    child.lua_get(
      ("require('logpose.report').build(%q, require('logpose.period').of('2026-10-02'), {}, '2026-10-15', %q)"):format(
        root,
        root .. "/reports/x.md"
      )
    ),
    "\n"
  )
  H.contains(report, "- Old work")
end

T["columns, blocked cards and overdue dates are coloured"] = function()
  child.cmd("Logpose board")
  local groups = child.lua_get([[(function()
    local seen = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      seen[m[4].hl_group] = true
    end
    return seen
  end)()]])
  for _, g in ipairs({
    "LogposeBoardColumn1",
    "LogposeBoardColumn3",
    "LogposeBoardFocus",
    "LogposeBoardBlocked",
    "LogposeBoardOverdue",
    "LogposeBoardTag",
    "LogposeProject_acme", -- each project in its own colour, from the colour scheme
    "LogposeProject_thesis",
  }) do
    eq({ g, groups[g] }, { g, true })
  end
  local function link(g)
    return child.lua_get(("vim.api.nvim_get_hl(0, { name = %q }).link"):format(g))
  end
  eq(link("LogposeProject_acme") ~= link("LogposeProject_thesis"), true)
  -- a project page's color: wins
  H.write(root .. "/projects/acme.md", '---\ntitle: "Acme"\nproject: acme\ncolor: "#ff0000"\n---\n')
  child.type_keys("r")
  eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'LogposeProject_acme' }).fg"), 0xff0000)
  -- linked to standard groups, so colour schemes style them; users can override
  eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'LogposeBoardColumn3' }).link"), "DiagnosticWarn")
end

T["D deletes a card after asking"] = function()
  child.cmd("Logpose board")
  child.lua([[vim.ui.select = function(items, opts, cb) _G.prompt = opts.prompt; cb('Cancel') end]])
  child.type_keys("D") -- focused: Read paper (Backlog)
  H.contains(child.lua_get("_G.prompt"), 'Delete "Read paper"?')
  eq(H.read(root .. "/tasks/read-paper.md") ~= nil, true)
  child.lua([[vim.ui.select = function(items, opts, cb) cb('Delete') end]])
  child.type_keys("D")
  eq(H.read(root .. "/tasks/read-paper.md"), nil)
  H.contains(screen(), "● Backlog (0)")
  H.contains(child.notifications()[#child.notifications()].msg, "deleted read-paper.md")
end

T["time in the column shows once a card is stale; stale cards fade, blocked ones don't"] = function()
  local function groups()
    return child.lua_get([[(function()
      local seen = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
        seen[m[4].hl_group] = true
      end
      return seen
    end)()]])
  end
  child.cmd("Logpose board")
  -- Queue design has sat 6 days, Fix flaky test 5: under the 7-day threshold, nothing shows
  eq(screen():find("idle", 1, true), nil)
  eq(groups().LogposeBoardFaded, nil)
  setup("{ board = { stale_days = 5 } }")
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, "◆ acme · idle 6d") -- Queue design: created 2026-10-09, no move logged
  H.contains(s, "overdue 1d · idle 5d") -- Fix flaky test: created 2026-10-10
  task(
    "moved",
    { title = "Moved recently", status = "todo", created = "2026-09-01" },
    "\n## Log\n\n- 2026-10-14 09:00: Backlog → TODO\n"
  )
  child.type_keys("r")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find("Moved recently", 1, true) then
      -- the log says it reached TODO yesterday: not stale
      eq((lines[i + 1] or ""):find("idle", 1, true), nil)
    end
  end
  local g = groups()
  eq({ g.LogposeBoardStale, g.LogposeBoardFaded }, { true, true })
  -- the blocked card isn't faded: what blocks it matters
  local faded = child.lua_get([[(function()
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      if m[4].hl_group == "LogposeBoardFaded" then
        local line = vim.api.nvim_buf_get_lines(0, m[2], m[2] + 1, false)[1]
        table.insert(out, line:sub(m[3] + 1, m[4].end_col))
      end
    end
    return out
  end)()]])
  eq(vim.tbl_contains(faded, "Queue design"), false)
  eq(vim.tbl_contains(faded, "Fix flaky test"), true)
end

T["due dates read as words, coloured by urgency"] = function()
  local function due(d, status)
    return child.lua_get(
      ("{ require('logpose.board.cards').due_text({ due = %q, status = %q }, '2026-10-15') }"):format(
        d,
        status or "todo"
      )
    )
  end
  eq(due("2026-10-13"), { "overdue 2d", "LogposeBoardOverdue" })
  eq(due("2026-10-15"), { "due today", "LogposeBoardDueSoon" })
  eq(due("2026-10-16"), { "due tomorrow", "LogposeBoardDueSoon" })
  eq(due("2026-10-20"), { "due Tue", "LogposeBoardDue" })
  eq(due("2026-11-03"), { "due 3 Nov", "LogposeBoardDue" })
  eq(due("2026-10-13", "done"), {}) -- done: no date
end

T["details fit by importance: the date stays whole, then the project, then whole tags"] = function()
  local function details(it, width)
    return child.lua_get(([[table.concat(vim.tbl_map(function(c) return c[1] end,
      require('logpose.board.cards').details(%s, '2026-10-15', true, %d)))]]):format(it, width))
  end
  local it = "{ project = 'thesis-work', due = '2026-10-16', status = 'todo', tags = { 'writing', 'ch3' } }"
  eq(details(it, 60), "◆ thesis-work · due tomorrow  #writing   #ch3 ") -- tags are chips
  eq(details(it, 40), "◆ thesis-work · due tomorrow  #writing ")
  eq(details(it, 24), "◆ thesis… · due tomorrow")
  eq(details(it, 18), "◆ due tomorrow") -- too short for a name: the colour mark alone
end

T["the focused card has a background; a one-project board leaves the project off its cards"] = function()
  setup(("{ projects = { paths = { [%q] = 'acme' } } }"):format(child.fn.getcwd()))
  child.o.cursorline = true -- as LazyVim sets it
  child.cmd("Logpose board")
  eq(child.wo.cursorline, false) -- no band across the board: the card has its own background
  eq(title(), "Board · acme")
  local s = screen()
  eq(s:find("◆ acme", 1, true), nil)
  H.contains(s, "overdue 1d  #perf ")
  child.type_keys("l") -- Backlog is empty on this board: go to a card
  local bg_rows = child.lua_get([[(function()
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      if m[4].hl_group == "LogposeBoardFocusBg" then
        rows[#rows + 1] = m[2]
      end
    end
    return rows
  end)()]])
  eq(#bg_rows >= 3, true) -- the whole card: borders, title, details
  child.type_keys("p") -- all projects: the project is back
  H.contains(screen(), "◆ acme")
end

T["card borders: the column's colour by default, or the project's, or neutral"] = function()
  local function border_groups()
    return child.lua_get([[(function()
      local seen = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
        seen[m[4].hl_group] = true
      end
      return seen
    end)()]])
  end
  child.o.termguicolors = true
  child.cmd("Logpose board")
  local g = border_groups()
  eq(g.LogposeBoardBorder, nil)
  eq(g.LogposeBoardColumn2, true) -- the TODO card, in TODO's colour
  child.cmd("bwipeout")
  setup("{ board = { border = 'project' } }")
  child.cmd("Logpose board")
  child.type_keys("l") -- off the thesis card: the focused one has the focus border
  g = border_groups()
  eq(g.LogposeProjectBorder_acme, true)
  eq(g.LogposeProjectBorder_thesis, true)
  -- the project's colour, mixed with the background: a different colour from the project's own
  local function fg(name)
    return child.lua_get(("vim.api.nvim_get_hl(0, { name = %q, link = false }).fg"):format(name))
  end
  eq(fg("LogposeProjectBorder_acme") ~= nil, true)
  eq(fg("LogposeProjectBorder_acme") ~= fg("LogposeProject_acme"), true)
  child.cmd("bwipeout")
  setup("{ board = { border = 'neutral' } }")
  child.cmd("Logpose board")
  g = border_groups()
  eq({ g.LogposeBoardBorder, g.LogposeProjectBorder_acme }, { true, nil })
  MiniTest.expect.error(function()
    setup("{ board = { border = 'rainbow' } }")
  end, "board.border")
end

T["tags are chips: their own background, readable in any colour scheme"] = function()
  child.o.termguicolors = true
  child.cmd("Logpose board")
  local hl = child.lua_get("vim.api.nvim_get_hl(0, { name = 'LogposeBoardTag', link = false })")
  local normal = child.lua_get("vim.api.nvim_get_hl(0, { name = 'Normal', link = false })")
  eq(hl.fg, normal.fg) -- plain text colour, not a dim one
  eq(hl.bg ~= nil and hl.bg ~= normal.bg, true)
  eq(hl.italic, nil)
end

T["compact cards follow the same rules"] = function()
  child.cmd("Logpose board")
  child.type_keys("c")
  local s = screen()
  H.contains(s, "• Fix flaky test")
  H.contains(s, "overdue 1d")
  H.contains(s, "⊘ Queue design")
  H.contains(s, "✓ Ship it")
end

T["WIP limits show in the header and turn red above it"] = function()
  child.cmd("Logpose board")
  H.contains(screen(), "● In progress (1/3)")
  task("w2", { title = "W2", status = "in-progress" })
  task("w3", { title = "W3", status = "in-progress" })
  task("w4", { title = "W4", status = "in-progress" })
  child.type_keys("r")
  H.contains(screen(), "● In progress (4/3)")
  local over = child.lua_get([[(function()
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      if m[4].hl_group == "LogposeBoardOverLimit" then return true end
    end
    return false
  end)()]])
  eq(over, true)
end

T["columns scroll on their own and keep the focused card in view"] = function()
  child.o.lines = 20
  for i = 1, 8 do
    task("b" .. i, { title = "Backlog " .. i, status = "backlog", created = ("2026-10-0%d"):format(i) })
  end
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, "↓ ")
  eq(s:find("↑", 1, true), nil)
  H.contains(s, "● In progress (1/3)") -- the other columns stay put
  child.type_keys("G")
  s = screen()
  H.contains(s, "↑ ")
  H.contains(s, "┏━") -- the focused (last) card is drawn
  H.contains(s, "Read paper") -- created 10-11: the last Backlog card
  child.type_keys("gg")
  eq(screen():find("↑", 1, true), nil)
end

T["z folds a column to a strip and back"] = function()
  child.cmd("Logpose board")
  child.type_keys("llll", "z") -- Done
  local s = screen()
  H.contains(s, "▸1")
  eq(s:find("Ship it", 1, true), nil)
  child.type_keys("z")
  H.contains(screen(), "● Done (1)")
  setup("{ board = { collapsed = { 'backlog' } } }")
  child.cmd("Logpose board")
  H.contains(screen(), "▸1")
  eq(screen():find("Read paper", 1, true), nil)
end

T["K peeks at the task in a float; closing saves and refreshes"] = function()
  child.cmd("Logpose board")
  child.type_keys("K") -- Read paper
  eq(child.api.nvim_buf_get_name(0), root .. "/tasks/read-paper.md")
  eq(child.api.nvim_win_get_config(0).relative, "editor")
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "notes from the peek" })
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-board")
  H.contains(H.read(root .. "/tasks/read-paper.md"), "notes from the peek")
  -- the close keys don't stay on the task buffer
  eq(
    child.lua_get(
      ("vim.api.nvim_buf_call(vim.fn.bufnr(%q), function() return vim.fn.maparg('q', 'n') end)"):format(
        root .. "/tasks/read-paper.md"
      )
    ),
    ""
  )
end

T["redraws to fit when a sidebar opens or closes, and ignores the editor's columns"] = function()
  child.o.statuscolumn = "%s%l " -- like LazyVim's
  child.o.foldcolumn = "1"
  child.o.sidescrolloff = 8
  child.cmd("Logpose board")
  local function fits()
    child.lua("vim.wait(100, function() return false end)")
    return child.lua_get([[(function()
      local buf = vim.fn.bufnr("logpose://board")
      local win = vim.fn.bufwinid(buf)
      local info = vim.fn.getwininfo(win)[1]
      local widest = 0
      for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        widest = math.max(widest, vim.fn.strdisplaywidth(l))
      end
      local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
      return { textoff = info.textoff, fits = widest <= info.width - info.textoff, leftcol = leftcol, width = info.width }
    end)()]])
  end
  local r = fits()
  eq({ r.textoff, r.fits, r.leftcol }, { 0, true, 0 })
  child.cmd("topleft vsplit | enew | vertical resize 40") -- an explorer; focus stays there
  r = fits()
  eq({ r.fits, r.leftcol }, { true, 0 })
  eq(r.width < 160, true)
  child.cmd("close")
  r = fits()
  eq({ r.fits, r.width }, { true, 160 })
  H.contains(screen(), "● Done (1)") -- full width again: Done back on the first row
end

T["u undoes board changes exactly and <C-r> redoes them"] = function()
  local flaky = root .. "/tasks/fix-flaky.md"
  local original = H.read(flaky)
  child.cmd("Logpose board")
  child.type_keys("l", "L") -- Fix flaky test: TODO -> In progress
  eq(status(flaky), "in-progress")
  child.type_keys("u")
  eq(H.read(flaky), original) -- the log line and timestamps are gone too
  H.contains(child.notifications()[#child.notifications()].msg, "undid move")
  child.type_keys("<C-r>")
  eq(status(flaky), "in-progress")
  child.type_keys("u")
  eq(H.read(flaky), original)
  -- adding and deleting cards undo too
  child.lua([[vim.ui.input = function(_, cb) cb('Undo me') end]])
  child.type_keys("a")
  eq(H.read(root .. "/tasks/undo-me.md") ~= nil, true)
  child.type_keys("u")
  eq(H.read(root .. "/tasks/undo-me.md"), nil)
  child.lua([[vim.ui.select = function(_, _, cb) cb('Delete') end]])
  child.type_keys("gg", "D")
  local gone = child.lua_get("vim.tbl_count(vim.fn.globpath(" .. vim.inspect(root .. "/tasks") .. ", '*.md', 0, 1))")
  child.type_keys("u")
  eq(child.lua_get("vim.tbl_count(vim.fn.globpath(" .. vim.inspect(root .. "/tasks") .. ", '*.md', 0, 1))"), gone + 1)
  child.type_keys("u", "u", "u")
  H.contains(child.notifications()[#child.notifications()].msg, "nothing to undo")
end

T["undo refuses when the task changed since"] = function()
  local flaky = root .. "/tasks/fix-flaky.md"
  child.cmd("Logpose board")
  child.type_keys("l", "L")
  H.write(flaky, H.read(flaky) .. "\nedited elsewhere\n")
  child.type_keys("u")
  H.contains(child.notifications()[#child.notifications()].msg, "can't undo move: the task changed since")
  H.contains(H.read(flaky), "edited elsewhere")
end

T["c switches to one-line cards"] = function()
  child.cmd("Logpose board")
  child.type_keys("c")
  local s = screen()
  eq(s:find("╭", 1, true), nil)
  H.contains(s, "▶ Read paper") -- the focused card
  H.contains(s, "• Fix flaky test")
  H.contains(s, "⊘ Queue design") -- blocked
  H.contains(title(), "compact")
  child.type_keys("l", "L") -- moves still work
  eq(status(root .. "/tasks/fix-flaky.md"), "in-progress")
end

T["v marks cards; H/L, x and e then act on all of them, as one undo step"] = function()
  child.cmd("Logpose board")
  local function marked_files()
    return child.lua_get([[vim.tbl_keys(require('logpose.board').boards[vim.fn.bufnr('logpose://board')].marked)]])
  end
  child.type_keys("v") -- Read paper, in Backlog
  H.contains(title(), "1 marked")
  H.contains(screen(), "━ ✓ ━") -- on the top border (still focused: the only card here)
  child.type_keys("l", "v") -- Fix flaky test, in TODO
  H.contains(title(), "2 marked")
  eq(#marked_files(), 2)
  child.type_keys("L")
  eq(status(root .. "/tasks/read-paper.md"), "todo")
  eq(status(root .. "/tasks/fix-flaky.md"), "in-progress")
  H.contains(child.notifications()[#child.notifications()].msg, "moved 2 of 2 marked cards · u undoes")
  child.type_keys("u") -- both at once
  eq(status(root .. "/tasks/read-paper.md"), "backlog")
  eq(status(root .. "/tasks/fix-flaky.md"), "todo")
  -- e edits them together: fields they share are filled in, the others left "as is"
  child.type_keys("e")
  eq(child.bo.filetype, "logpose-edit")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "", "", "", "", "" })
  child.api.nvim_buf_set_lines(0, 1, 2, false, { "thesis" })
  child.api.nvim_buf_set_lines(0, 2, 3, false, { "+urgent" })
  child.cmd("write")
  child.type_keys("q")
  eq(child.bo.filetype, "logpose-board")
  local fix = H.read(root .. "/tasks/fix-flaky.md")
  H.contains(fix, "project: thesis")
  H.contains(fix, "tags: [perf, urgent]") -- kept its own tag
  H.contains(H.read(root .. "/tasks/read-paper.md"), "tags: [urgent]")
  eq(status(root .. "/tasks/fix-flaky.md"), "todo") -- status left as it was
  child.type_keys("u")
  H.contains(H.read(root .. "/tasks/fix-flaky.md"), "project: acme")
  -- x finishes both; V unmarks
  child.type_keys("x")
  eq(status(root .. "/tasks/read-paper.md"), "done")
  eq(status(root .. "/tasks/fix-flaky.md"), "done")
  child.type_keys("V")
  eq(#marked_files(), 0)
  eq(title():find("marked", 1, true), nil)
end

T["s groups the cards into rows per project"] = function()
  child.cmd("Logpose board")
  child.type_keys("s")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local function row_of(text)
    for i, l in ipairs(lines) do
      if l:find(text, 1, true) then
        return i
      end
    end
  end
  local acme, thesis = row_of("◆ acme ─"), row_of("◆ thesis ─")
  assert(acme and thesis and acme < thesis, "lanes in project order")
  assert(row_of("Fix flaky test") > acme and row_of("Fix flaky test") < thesis)
  assert(row_of("Read paper") > thesis)
  H.contains(title(), "by project")
  for _, l in ipairs(lines) do
    eq(l:match("%s$"), nil)
  end
end

T["icons can be ascii or nerd font"] = function()
  setup("{ board = { icons = 'ascii' } }")
  child.cmd("Logpose board")
  local s = screen()
  H.contains(s, "* Backlog (1)")
  H.contains(s, "+---")
  H.contains(s, "#===") -- focused
  H.contains(s, "! waiting on ana")
  H.contains(s, "+ acme  overdue 1d  #perf")
  H.contains(s, "v Ship it")
  eq(s:find("[╭◆◷⊘●]"), nil)
  -- long titles are cut with "~", not "…": the whole board is plain ASCII
  task("long", { title = "A very long task title that cannot possibly fit on one card line", status = "todo" })
  child.type_keys("r")
  s = screen()
  eq(s:find("…", 1, true), nil)
  eq(s:find("[\128-\255]"), nil)
  setup("{ board = { icons = 'nerd' } }")
  child.cmd("Logpose board")
  H.contains(screen(), vim.fn.nr2char(0xf07b) .. " acme")
end

T["board.open = 'tab' opens it in its own tab; q closes the tab"] = function()
  setup("{ board = { open = 'tab' } }")
  child.cmd("Logpose board")
  eq(#child.api.nvim_list_tabpages(), 2)
  eq(child.bo.filetype, "logpose-board")
  child.type_keys("q")
  eq(#child.api.nvim_list_tabpages(), 1)
end

T["a moved card flashes"] = function()
  child.cmd("Logpose board")
  child.lua("require('logpose.board').flash_ms = 10000")
  child.type_keys("l", "L")
  local flashed = child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.board.flash"]
    return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
  end)()]])
  eq(flashed > 0, true)
end

return T

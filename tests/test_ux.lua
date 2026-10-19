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

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua("vim.g.mapleader = ' '")
      setup()
      H.freeze(child, 2026, 10, 16) -- Friday
    end,
    post_once = child.stop,
  },
})

T["keymaps"] = MiniTest.new_set()

T["keymaps"]["are off by default"] = function()
  eq(child.fn.maparg(" jd", "n"), "")
end

T["keymaps"]["keymaps = true installs <leader>j… without touching your own maps"] = function()
  child.lua([[vim.keymap.set("n", " jk", ":echo 'mine'<cr>")]])
  setup("{ keymaps = true }")
  eq(child.fn.maparg(" jd", "n"), "<Plug>(logpose-daily)")
  eq(child.fn.maparg(" jx", "x"), "<Plug>(logpose-done)")
  eq(child.fn.maparg(" jj", "n"), "<Cmd>Logpose<CR>")
  eq(child.fn.maparg(" jk", "n"), ":echo 'mine'<CR>") -- left alone
  eq(child.lua_get("vim.fn.maparg(' jd', 'n', false, true).desc"), "Daily note")
  setup("{ keymaps = { prefix = '<leader>n' } }")
  eq(child.fn.maparg(" nd", "n"), "<Plug>(logpose-daily)")
end

T["notifications carry a title; the prefix goes when a notifier shows titles"] = function()
  child.lua(
    [[vim.notify = function(msg, level, opts) _G.n = { msg = msg, level = level, title = opts and opts.title } end]]
  )
  child.lua("require('logpose.util.ui').notify('logpose: captured to Backlog')")
  eq(child.lua_get("_G.n"), { msg = "logpose: captured to Backlog", level = vim.log.levels.INFO, title = "logpose" })
  child.lua("package.loaded['snacks.notifier'] = {}")
  child.lua("require('logpose.util.ui').notify('logpose: captured to Backlog', vim.log.levels.WARN)")
  eq(child.lua_get("_G.n"), { msg = "Captured to Backlog", level = vim.log.levels.WARN, title = "logpose" })
end

T["today shows the day at a glance and opens what you pick"] = function()
  setup("{ period = { kind = 'sprint', sprint = { anchor = '2026-10-15', first_number = 43 } } }")
  H.write(root .. "/tasks/a.md", '---\ntitle: "Fix flaky"\nstatus: in-progress\nproject: acme\ndue: 2026-10-14\n---\n')
  H.write(root .. "/tasks/b.md", '---\ntitle: "Queue"\nstatus: todo\nblocked: waiting on ana\ndue: 2026-10-18\n---\n')
  H.write(root .. "/tasks/c.md", '---\ntitle: "Later"\nstatus: todo\ndue: 2026-11-30\n---\n')
  H.write(
    root .. "/meetings/2026-10-16 - retro.md",
    '---\ntype: retro\ndate: 2026-10-16\ntitle: "Retro"\nproject: acme\n---\n## Action items\n\n- [ ] write ADR @ana due:2026-10-10\n'
  )
  H.write(root .. "/daily/daily-2026-10-16.md", "# d\n\n## Today\n\n- [ ] review PR\n- [x] done\n\n## Blockers\n")
  child.cmd("Logpose today")
  local s = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(s, "# Today · Friday 2026-10-16  ·  sprint-43, day 2 of 10")
  H.contains(s, "## Meetings (1)\n\n- Retro  ◆ acme")
  H.contains(s, "## In progress (1)\n\n- Fix flaky  ◆ acme")
  H.contains(s, "## Blocked (1)\n\n- Queue: waiting on ana")
  H.contains(s, "## Due soon (2)\n\n- Fix flaky  (overdue 2d)  ◆ acme\n- Queue  (due Sun)") -- as on the board
  H.contains(s, "## Overdue action items (1)\n\n- write ADR @ana  (overdue 6d)  ◆ acme")
  H.contains(s, "## Left in today's note (1)\n\n- [ ] review PR")
  eq(s:find("Later", 1, true), nil)
  -- <CR> opens the item at its line
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find("write ADR", 1, true) then
      child.api.nvim_win_set_cursor(0, { i, 0 })
    end
  end
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-16 - retro.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 9)
end

T["today lists the notes edited lately, newest first"] = function()
  local uv = vim.uv or vim.loop
  local now = os.time()
  local function note(path, text, ago)
    H.write(root .. "/" .. path, text)
    uv.fs_utime(root .. "/" .. path, now - ago, now - ago)
  end
  note("notes/ideas.md", "# Ideas\n", 2 * 3600)
  note("meetings/2026-10-14 - sync.md", '---\ntitle: "Sync"\nproject: acme\n---\n', 26 * 3600)
  note("notes/old.md", "# Old\n", 10 * 86400) -- too long ago
  note("tasks/t.md", '---\ntitle: "A task"\nstatus: todo\n---\n', 60) -- tasks are on the board
  note("daily/daily-2026-10-16.md", "# d\n", 60) -- today's note has its own section
  child.cmd("Logpose today")
  local s = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(s, "## Recently edited (2)\n\n- Ideas  (2h ago)\n- Sync  (yesterday)  ◆ acme")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find("Ideas", 1, true) then
      child.api.nvim_win_set_cursor(0, { i, 0 })
    end
  end
  child.type_keys("<CR>")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "ideas.md")
end

T["today with nothing on says so"] = function()
  child.cmd("Logpose today")
  local s = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(s, "## Meetings (0)\n\n  nothing")
  child.type_keys("q")
  eq(child.bo.filetype ~= "markdown" or child.api.nvim_buf_get_name(0) ~= "logpose://today", true)
end

return T

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
      setup()
      H.write(root .. "/INBOX.md", "# INBOX\n\n## 2026-10-13\n- [ ] fix flaky test #perf #acme\n- [x] ship #perf\n")
      H.write(
        root .. "/meetings/acme/2026-10-14 - retro.md",
        '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\ntags: [team]\n---\n# Retro\n- [ ] follow up #perf\n'
      )
      H.write(
        root .. "/meetings/thesis/2026-10-10 - advisor.md",
        "---\ntype: 1on1\ndate: 2026-10-10\nproject: thesis\n---\n# Advisor\n- [ ] read paper #ux\n"
      )
      H.write(root .. "/daily/daily-2026-10-14.md", "# 2026-10-14 daily notes\nIdea: #ux spike\n")
    end,
    post_once = child.stop,
  },
})

--- Capture what vim.ui.select is offered; pick the item whose label contains `pick`.
local function select_picks(...)
  child.lua(("_G.picks = { %s }"):format(table.concat(
    vim.tbl_map(function(s)
      return vim.inspect(s)
    end, { ... }),
    ", "
  )))
  child.lua([[
    _G.offered = {}
    vim.ui.select = function(items, opts, cb)
      local labels = vim.tbl_map(opts.format_item, items)
      table.insert(_G.offered, { prompt = opts.prompt, labels = labels })
      local want = table.remove(_G.picks, 1)
      for i, label in ipairs(labels) do
        if want and label:find(want, 1, true) then return cb(items[i]) end
      end
      cb(nil)
    end
  ]])
end

local function offered()
  return child.lua_get("_G.offered")
end

T["find meetings by project, newest first"] = function()
  select_picks("Retro")
  child.cmd("Logpose find meetings project:acme")
  eq(offered()[1].prompt, "Meetings project:acme")
  eq(offered()[1].labels, { "2026-10-14  meeting/retro  Retro  @acme" })
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-14 - retro.md")
end

T["find notes (default scope) sorts by date"] = function()
  select_picks()
  child.cmd("Logpose find")
  local labels = offered()[1].labels
  eq(#labels, 4)
  H.contains(labels[1], "2026-10-14")
  H.contains(labels[3], "2026-10-10  meeting/1on1  Advisor  @thesis")
  H.contains(labels[4], "----------  inbox  INBOX")
end

T["find tasks: open first, filters, opens at the line"] = function()
  select_picks("fix flaky")
  child.cmd("Logpose find tasks #perf")
  eq(offered()[1].labels, {
    "[ ] follow up #perf  · Retro  @acme",
    "[ ] fix flaky test #perf #acme  · INBOX",
    "[x] ship #perf  · INBOX",
  })
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "INBOX.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 4)
end

T["find tasks open project:acme matches frontmatter and tags"] = function()
  select_picks()
  child.cmd("Logpose find tasks open project:acme")
  eq(#offered()[1].labels, 2)
end

T["find tags, then everything carrying the chosen tag"] = function()
  select_picks("#ux", "spike")
  child.cmd("Logpose find tags")
  eq(offered()[1].labels, { "#perf (3)", "#ux (2)", "#acme (1)", "#team (1)" })
  eq(offered()[2].prompt, "#ux")
  eq(offered()[2].labels, { "Idea: #ux spike  · 2026-10-14 daily notes", "[ ] read paper #ux  · Advisor  @thesis" })
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "daily-2026-10-14.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
end

T["find projects, then its notes and tasks"] = function()
  select_picks("acme")
  child.cmd("Logpose find projects")
  eq(offered()[1].labels, { "acme (3)", "thesis (2)" })
  eq(offered()[2].prompt, "Project acme")
  eq(#offered()[2].labels, 3)
end

T["find decisions and blockers, with relative dates"] = function()
  H.write(
    root .. "/meetings/acme/2026-10-07 - planning.md",
    '---\ntype: planning\ndate: 2026-10-07\nproject: acme\ntitle: "Planning"\n---\n# Planning\n## Decisions\n- Drop IE support\n## Risks\n- infra delay\n'
  )
  H.write(
    root .. "/meetings/acme/2026-10-14 - retro.md",
    '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\n---\n# Retro\n## Decisions\n- Use Postgres\n## Blockers\n- waiting on infra\n'
  )
  H.freeze(child, 2026, 10, 14)
  select_picks()
  child.cmd("Logpose find decisions project:acme")
  eq(
    offered()[1].labels,
    { "Use Postgres  · Retro › Decisions  @acme", "Drop IE support  · Planning › Decisions  @acme" }
  )
  child.cmd("Logpose find decisions since:-3d")
  eq(offered()[2].labels, { "Use Postgres  · Retro › Decisions  @acme" })
  child.cmd("Logpose find blockers week:current")
  eq(offered()[3].labels, { "waiting on infra  · Retro › Blockers  @acme" })
  child.cmd("Logpose find tasks section:action")
  H.contains(child.notifications()[#child.notifications()].msg, "no matches")
  child.cmd("Logpose find notes section:risks")
  H.contains(child.notifications()[#child.notifications()].msg, "no matches")
end

T["sprint: filters use the configured sprints"] = function()
  setup("{ period = { sprint = { anchor = '2026-10-01', first_number = 42 } } }")
  H.freeze(child, 2026, 10, 14)
  select_picks()
  child.cmd("Logpose find meetings sprint:current") -- sprint 42: 2026-10-01 – 2026-10-14
  eq(#offered()[1].labels, 2)
  child.cmd("Logpose find meetings sprint:-1")
  H.contains(child.notifications()[1].msg, "no matches")
  child.cmd("Logpose find meetings sprint:42")
  eq(#offered()[2].labels, 2)
end

T["no matches says so"] = function()
  child.cmd("Logpose find tasks #nothing")
  H.contains(child.notifications()[1].msg, "no matches")
end

T["bad filters fail before searching"] = function()
  child.cmd("Logpose find tasks since:someday")
  H.contains(child.notifications()[1].msg, "needs a date")
end

T["completion"] = function()
  eq(
    child.fn.getcompletion("Logpose find ", "cmdline"),
    { "notes", "daily", "meetings", "archives", "tasks", "decisions", "blockers", "tags", "projects" }
  )
  local c = child.fn.getcompletion("Logpose find tasks ", "cmdline")
  for _, want in ipairs({ "open", "done", "project:acme", "project:thesis", "#perf", "#ux", "type:retro" }) do
    eq(vim.tbl_contains(c, want), true)
  end
  eq(child.fn.getcompletion("Logpose find tasks #p", "cmdline"), { "#perf" })
  eq(child.fn.getcompletion("Logpose grep ", "cmdline"), {})
end

T["grep without a picker plugin fills the quickfix list"] = function()
  child.cmd("Logpose grep follow up")
  local qf = child.fn.getqflist()
  eq(#qf, 1)
  eq(qf[1].lnum, 9)
  child.cmd("Logpose grep zzz-nothing")
  H.contains(child.notifications()[1].msg, 'no matches for "zzz-nothing"')
end

T["backends"] = MiniTest.new_set()

T["backends"]["snacks gets items with file positions and confirms"] = function()
  setup("{ picker = 'snacks' }")
  child.lua([[package.loaded["snacks"] = { picker = {
    pick = function(o)
      _G.o = { title = o.title, preview = o.preview, n = #o.items, first = o.items[1].text, file = o.items[1].file, pos = o.items[1].pos }
      o.confirm({ close = function() _G.closed = true end }, o.items[2])
    end,
    grep = function(o) _G.grep = o end,
  } }]])
  child.cmd("Logpose find tasks #perf")
  local o = child.lua_get("_G.o")
  eq({ o.title, o.preview, o.n, o.pos }, { "Tasks #perf", "file", 3, { 9, 0 } })
  eq(o.first, "[ ] follow up #perf  · Retro  @acme")
  eq(child.lua_get("_G.closed"), true)
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "INBOX.md")
  child.cmd("Logpose grep flaky")
  eq(child.lua_get("_G.grep"), { cwd = root, dirs = { root }, search = "flaky" })
end

T["backends"]["fzf-lua gets file:line entries relative to the journal"] = function()
  setup("{ picker = 'fzf_lua' }")
  child.lua([[package.loaded["fzf-lua"] = {
    fzf_exec = function(entries, o)
      _G.entries, _G.o = entries, { cwd = o.cwd, previewer = o.previewer, prompt = o.prompt }
      o.actions.default({ entries[2] })
    end,
    live_grep = function(o) _G.grep = o end,
  }]])
  child.cmd("Logpose find tasks #perf")
  eq(child.lua_get("_G.entries")[2], "INBOX.md:4: [ ] fix flaky test #perf #acme  · INBOX")
  eq(child.lua_get("_G.o"), { cwd = root, previewer = "builtin", prompt = "Tasks #perf> " })
  eq(child.api.nvim_win_get_cursor(0)[1], 4)
  child.cmd("Logpose grep flaky")
  eq(child.lua_get("_G.grep"), { cwd = root, search = "flaky" })
end

T["backends"]["telescope gets entries with filename and lnum"] = function()
  setup("{ picker = 'telescope' }")
  child.lua([[
    local selected
    package.loaded["telescope"] = {}
    package.loaded["telescope.finders"] = { new_table = function(t) return t end }
    package.loaded["telescope.config"] = { values = { generic_sorter = function() return "sorter" end, grep_previewer = function() return "previewer" end } }
    package.loaded["telescope.actions.state"] = { get_selected_entry = function() return selected end }
    local replaced
    package.loaded["telescope.actions"] = {
      select_default = { replace = function(_, fn) replaced = fn end },
      close = function() _G.closed = true end,
    }
    package.loaded["telescope.pickers"] = { new = function(_, spec)
      return { find = function()
        _G.spec = { title = spec.prompt_title, previewer = spec.previewer }
        spec.attach_mappings(1)
        selected = spec.finder.entry_maker(spec.finder.results[3])
        _G.entry = { display = selected.display, filename = selected.filename ~= nil, lnum = selected.lnum }
        replaced()
      end }
    end }
    package.loaded["telescope.builtin"] = { live_grep = function(o) _G.grep = o end }
  ]])
  child.cmd("Logpose find tasks #perf")
  eq(child.lua_get("_G.spec"), { title = "Tasks #perf", previewer = "previewer" })
  eq(child.lua_get("_G.entry"), { display = "[x] ship #perf  · INBOX", filename = true, lnum = 5 })
  eq(child.lua_get("_G.closed"), true)
  eq(child.api.nvim_win_get_cursor(0)[1], 5)
  child.cmd("Logpose grep flaky")
  eq(child.lua_get("_G.grep"), { cwd = root, default_text = "flaky" })
end

T["backends"]["auto prefers snacks, then fzf-lua, then telescope"] = function()
  child.lua([[package.loaded["telescope"] = {}; package.loaded["fzf-lua"] = {}]])
  eq(child.lua_get("require('logpose.picker').detect('auto')"), "fzf_lua")
  child.lua([[package.loaded["snacks"] = { picker = {} }]])
  eq(child.lua_get("require('logpose.picker').detect('auto')"), "snacks")
  eq(
    child.lua_get("{ require('logpose.picker').detect('nope') }"),
    { "select", 'unknown picker "nope"; using vim.ui.select' }
  )
end

return T

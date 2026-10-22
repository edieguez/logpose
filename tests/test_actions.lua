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
      H.freeze(child, 2026, 10, 14)
      H.write(root .. "/meetings/acme/2026-10-07 - retro.md", table.concat({
        "---",
        "type: retro",
        "date: 2026-10-07",
        "project: acme",
        'title: "Retro"',
        "series: acme/retro",
        "---",
        "# Retro",
        "- [ ] fix CI @ana due:2026-10-10",
        "- [ ] write docs @emmanuel due:2026-10-20",
        "- [ ] unassigned thing",
        "- [x] closed @ana",
        "- [ ] ",
      }, "\n") .. "\n")
      H.write(
        root .. "/meetings/thesis/2026-10-12 - advisor.md",
        '---\ntype: 1on1\ndate: 2026-10-12\nproject: thesis\ntitle: "Advisor"\n---\n# Advisor\n- [ ] read paper due:2026-10-15 #ux\n'
      )
      H.write(root .. "/daily/daily-2026-10-14.md", "# 2026-10-14 daily notes\n- [ ] daily task @emmanuel\n")
      H.write(root .. "/INBOX.md", "# INBOX\n- [ ] inbox task\n")
    end,
    post_once = child.stop,
  },
})

local function qf()
  return vim.tbl_map(function(e)
    return e.text
  end, child.fn.getqflist())
end

T["meta"] = function()
  local meta = function(s)
    return child.lua_get(("{ require('logpose.actions').meta(%q) }"):format(s))
  end
  eq(meta("fix @Ana and @bob.smith due:2026-10-10"), { { "ana", "bob.smith" }, "2026-10-10" })
  eq(meta("mail a@b.com due:2026-02-30"), { {} })
  eq(meta("nothing"), { {} })
end

T["open (default): meetings only, by due date, overdue flagged"] = function()
  child.cmd("Logpose actions")
  eq(qf(), {
    "[ ] fix CI @ana due:2026-10-10  (overdue)  · Retro  @acme",
    "[ ] read paper due:2026-10-15 #ux  · Advisor  @thesis",
    "[ ] write docs @emmanuel due:2026-10-20  · Retro  @acme",
    "[ ] unassigned thing  · Retro  @acme",
  })
  eq(child.fn.getqflist({ title = 1 }).title, "logpose actions: open")
  eq(child.fn.getqflist()[1].lnum, 9)
end

T["leaves the index's items alone"] = function()
  local count = ("#vim.tbl_filter(function(it) return it.due ~= nil end, require('logpose.index').build(%q))"):format(
    root
  )
  for _, f in ipairs(vim.fn.globpath(root, "**/*.md", true, true)) do
    vim.uv.fs_utime(f, os.time() - 60, os.time() - 60) -- old enough for the index to cache
  end
  eq(child.lua_get(count), 0)
  child.cmd("Logpose actions")
  eq(child.lua_get(count), 0)
end

T["overdue"] = function()
  child.cmd("Logpose actions overdue")
  eq(#qf(), 1)
  H.contains(qf()[1], "fix CI")
end

T["mine uses `me` and unassigned items"] = function()
  setup("{ me = '@Emmanuel' }")
  child.cmd("Logpose actions mine")
  eq(#qf(), 3) -- write docs, read paper (unassigned), unassigned thing
  setup("{ me = 'emmanuel', actions = { unassigned_mine = false } }")
  child.cmd("Logpose actions mine")
  eq(#qf(), 1)
  H.contains(qf()[1], "write docs")
end

T["mine without `me` lists unassigned items"] = function()
  child.cmd("Logpose actions mine")
  eq(#qf(), 2)
end

T["all includes closed items last"] = function()
  child.cmd("Logpose actions all")
  eq(#qf(), 5)
  H.contains(qf()[5], "[x] closed @ana")
end

T["filters work like :Logpose find"] = function()
  child.cmd("Logpose actions open project:thesis")
  eq(#qf(), 1)
  H.contains(qf()[1], "read paper")
  child.cmd("Logpose actions #ux")
  eq(#qf(), 1)
  child.cmd("Logpose actions all docs")
  eq(#qf(), 1)
end

T["relative date filters"] = function()
  child.cmd("Logpose actions open since:-3d")
  eq(#qf(), 1) -- only the 2026-10-12 advisor meeting is within 3 days
  H.contains(qf()[1], "read paper")
end

T["include_daily adds daily-note tasks"] = function()
  setup("{ actions = { include_daily = true } }")
  child.cmd("Logpose actions")
  eq(#qf(), 5)
end

T["picker output"] = function()
  setup("{ actions = { output = 'picker' } }")
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.labels = vim.tbl_map(opts.format_item, items); _G.prompt = opts.prompt; cb(items[2])
  end]])
  child.cmd("Logpose actions")
  eq(child.lua_get("_G.prompt"), "Actions: open")
  eq(#child.lua_get("_G.labels"), 4)
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-12 - advisor.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 8)
end

T["nothing to show"] = function()
  child.cmd("Logpose actions open project:nope")
  H.contains(child.notifications()[1].msg, "no open action items")
end

T["completion starts with modes"] = function()
  local c = child.fn.getcompletion("Logpose actions ", "cmdline")
  eq(vim.list_slice(c, 1, 4), { "open", "mine", "overdue", "all" })
  eq(vim.tbl_contains(c, "project:acme"), true)
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose actions mine ", "cmdline"), "#ux"), true)
end

return T

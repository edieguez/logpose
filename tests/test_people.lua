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
      H.write(
        root .. "/meetings/2026-10-07 - 1-1-ana.md",
        '---\ntype: 1on1\ndate: 2026-10-07\ntitle: "1:1 Ana"\nwith: "Ana"\nattendees: [Ana]\nseries: 1on1-ana\n---\n# 1:1 Ana\n- [ ] send feedback\n'
      )
      H.write(
        root .. "/meetings/2026-10-08 - retro.md",
        '---\ntype: retro\ndate: 2026-10-08\ntitle: "Retro"\nattendees: [Ana, Bob Smith]\n---\n# Retro\n- [ ] fix CI @ana\nPaired with @bob.smith on tests\n'
      )
      H.write(root .. "/INBOX.md", "# INBOX\n## 2026-10-13\n- [ ] ask @Ana about leave\n")
    end,
    post_once = child.stop,
  },
})

local function select_picks(...)
  child.lua(("_G.picks = %s"):format(vim.inspect({ ... })))
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

T["index collects people from attendees, with: and mentions"] = function()
  local people = child.lua_get(("require('logpose.index').people(require('logpose.index').build(%q))"):format(root))
  eq(people, {
    { slug = "ana", name = "Ana", count = 5 },
    { slug = "bob-smith", name = "Bob Smith", count = 2 },
  })
  eq(
    child.lua_get(
      "vim.tbl_map(function(m) return m.slug end, require('logpose.index').mentions_in('x @Ana, mail a@b.com (@bob.smith.)'))"
    ),
    { "ana", "bob-smith" }
  )
end

T["find people, then everything involving them"] = function()
  select_picks("Bob Smith")
  child.cmd("Logpose find people")
  eq(child.lua_get("_G.offered")[1].labels, { "Ana (5)", "Bob Smith (2)" })
  local second = child.lua_get("_G.offered")[2]
  eq(second.prompt, "Bob Smith")
  eq(second.labels, { "2026-10-08  meeting/retro  Retro", "Paired with @bob.smith on tests  · Retro" })
end

T["person: and @ filters"] = function()
  select_picks()
  child.cmd("Logpose find tasks @ana")
  eq(#child.lua_get("_G.offered")[1].labels, 2) -- fix CI, ask about leave
  child.cmd("Logpose find meetings person:bob-smith")
  eq(child.lua_get("_G.offered")[2].labels, { "2026-10-08  meeting/retro  Retro" })
  child.cmd("Logpose actions person:ana")
  local qf = child.fn.getqflist()
  eq(#qf, 1)
  H.contains(qf[1].text, "fix CI @ana")
end

T["1:1 notes record the person as with: and attendee"] = function()
  child.lua("vim.ui.input = function(opts, cb) _G.completion = opts.completion; cb('Bob Smith') end")
  child.cmd("Logpose meeting 1on1")
  local content = H.read(root .. "/meetings/2026-10-14 - 1-1-bob-smith.md")
  H.contains(content, 'with: "Bob Smith"\nattendees: [Bob Smith]\n')
  eq(child.lua_get("_G.completion"), "customlist,v:lua.LogposeCompleteTitles")
end

T["ask_attendees asks with people completion"] = function()
  setup("{ meeting_types = { retro = { ask_attendees = true } } }")
  child.lua(
    [[vim.ui.input = function(opts, cb) _G.prompt, _G.completion = opts.prompt, opts.completion; cb("Ana, @carol, Bob: QA") end]]
  )
  child.cmd("Logpose meeting retro")
  eq(child.lua_get("_G.prompt"), "Attendees (comma separated): ")
  eq(child.lua_get("_G.completion"), "customlist,v:lua.LogposeCompletePeople")
  H.contains(H.read(root .. "/meetings/2026-10-14 - retro.md"), 'attendees: [Ana, carol, "Bob: QA"]\n')
end

T["completion of people and past titles"] = function()
  child.lua("require('logpose.people')")
  eq(child.lua_get("LogposeCompletePeople('a')"), { "Ana" })
  eq(child.lua_get("LogposeCompletePeople('Ana, b')"), { "Ana, Bob Smith" })
  H.write(
    root .. "/meetings/2026-10-01 - arch-sync.md",
    '---\ntype: adhoc\ndate: 2026-10-01\ntitle: "Arch sync"\n---\n# Arch sync\n'
  )
  child.lua("require('logpose.notes.meeting')._completing = 'adhoc'")
  eq(child.lua_get("LogposeCompleteTitles('ar')"), { "Arch sync" })
  child.lua("require('logpose.notes.meeting')._completing = '1on1'")
  eq(child.lua_get("LogposeCompleteTitles('')"), { "Ana", "Bob Smith" })
end

T["completion offers person: filters"] = function()
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose find tasks ", "cmdline"), "person:bob-smith"), true)
end

return T

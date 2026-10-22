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
  local people = child.lua(([[
    local counts, names = {}, {}
    for _, it in ipairs(require('logpose.index').build(%q)) do
      for _, slug in ipairs(it.people or {}) do
        counts[slug] = (counts[slug] or 0) + 1
      end
      names = vim.tbl_extend("keep", names, it.names or {})
    end
    return { counts, names }
  ]]):format(root))
  eq(people, { { ana = 5, ["bob-smith"] = 2 }, { ana = "Ana", ["bob-smith"] = "Bob Smith" } })
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
  eq(child.lua_get("_G.offered")[1].labels, { "Ana · 5 notes", "Bob Smith · 2 notes" })
  local second = child.lua_get("_G.offered")[2]
  eq(second.prompt, "Bob Smith")
  eq(second.labels, { "2026-10-08  meeting/retro  Retro", "Paired with @bob.smith on tests  · Retro" })
end

T["person: and @ filters"] = function()
  select_picks()
  child.cmd("Logpose find todos @ana")
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

--- A person's page.
local function person(slug, fm)
  H.write(root .. "/people/" .. slug .. ".md", "---\n" .. fm .. "\n---\n## Notes\n")
end

T["people pages add people you haven't met yet; aliases make one person"] = function()
  person("ana-lopez", 'name: "Ana López"\naliases: [Ana]\nemail: ana@acme.com\nslack: ana.lopez\nprojects: [acme]')
  person("jose-ruiz", 'name: "José Ruiz"\nrole: Designer')
  local known = child.lua_get([[vim.tbl_map(function(p)
    return { p.slug, p.name, p.count, p.contacts.email or false, p.page and vim.fs.basename(p.page) or false }
  end, require('logpose.people').known())]])
  eq(known, {
    { "ana-lopez", "Ana López", 5, "ana@acme.com", "ana-lopez.md" }, -- "Ana" and @ana are her
    { "bob-smith", "Bob Smith", 2, false, false }, -- mentioned, no page
    { "jose-ruiz", "José Ruiz", 0, false, "jose-ruiz.md" },
  })
  -- person: filters and the find screen go by the person, any name
  select_picks()
  child.cmd("Logpose find todos person:ana-lopez")
  eq(#child.lua_get("_G.offered")[1].labels, 2) -- fix CI @ana, ask @Ana about leave: by her alias
end

T["matching: any part of the name, accents ignored, the project's people first"] = function()
  person("ana-lopez", 'name: "Ana López"\nprojects: [acme]')
  person("jose-ruiz", 'name: "José Ruiz"\nprojects: [thesis]')
  person("lola-ortiz", 'name: "Lola Ortiz"\nprojects: [acme]')
  local function names(q, project)
    return child.lua_get(
      ("vim.tbl_map(function(p) return p.name end, require('logpose.people').match(require('logpose.people').known(), %q, %s))"):format(
        q,
        project and ("%q"):format(project) or "nil"
      )
    )
  end
  eq(names("lop"), { "Ana López" }) -- a word of the name
  eq(names("jose"), { "José Ruiz" }) -- no accent typed
  eq(names("smi"), { "Bob Smith" })
  eq(names("@bob"), { "Bob Smith" })
  eq(names("ana"), { "Ana", "Ana López" }) -- the name's start, most involved first
  eq(names("l"), { "Lola Ortiz", "Ana López" }) -- start of the name before a later word
  eq(names("", "thesis")[1], "José Ruiz") -- this project's people first
  eq(child.lua_get("LogposeCompletePeople('Ana, lop')"), { "Ana, Ana López" })
end

T["the edit form completes attendees from any part of the name"] = function()
  person("ana-lopez", 'name: "Ana López"\nrole: Backend lead\nslack: ana.lopez')
  local words = child.lua_get(
    [[vim.tbl_map(function(it) return it.word end,
    require('logpose.edit.form').candidates(..., 'meeting', 'attendees', 'lop', {}))]],
    { root }
  )
  eq(words, { "Ana López" })
  local menu =
    child.lua_get("require('logpose.edit.form').candidates(..., 'meeting', 'attendees', 'lop', {})[1].menu", { root })
  eq(menu, "Backend lead · ana.lopez") -- no `show` configured for slack: the value as is
end

T["typing in the form's attendees keeps the menu on matches anywhere in the name"] = function()
  person("ana-lopez", 'name: "Ana López"')
  person("lola-ortiz", 'name: "Lola Ortiz"')
  child.cmd("edit " .. root .. "/meetings/2026-10-08 - retro.md")
  child.cmd("Logpose edit")
  for i, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l == "Ana, Bob Smith" then
      child.api.nvim_win_set_cursor(0, { i, #l })
    end
  end
  child.type_keys("A", ", l")
  local function menu()
    return child.lua_get("vim.tbl_map(function(it) return it.word end, vim.fn.complete_info({ 'items' }).items)")
  end
  eq(menu(), { "Lola Ortiz", "Ana López" })
  child.type_keys("o", "p") -- "lop": only a later word of the name matches
  eq(menu(), { "Ana López" })
  child.type_keys("<Esc>")
end

T["in a note: attendees, with: and @mentions complete people"] = function()
  person("ana-lopez", 'name: "Ana López"')
  local path = root .. "/meetings/acme/2026-10-14 - sync.md"
  H.write(path, '---\ntitle: "Sync"\nproject: acme\nattendees: [Ana]\n---\n')
  child.cmd("edit " .. path)
  -- being typed (not saved, so not in the index yet)
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---",
    'title: "Sync"',
    "project: acme",
    "attendees: [Ana, lop",
    "with: bo",
    "---",
    "ask @jo and @smi",
  })
  local function items(row, col)
    return child.lua_get(
      ([[vim.tbl_map(function(it) return { it.label, it.textEdit.newText, it.textEdit.range.start.character } end,
        require('logpose.completion').items(vim.api.nvim_buf_get_lines(0, %d, %d, false)[1], %d, %d, 0))]]):format(
        row,
        row + 1,
        col,
        row
      )
    )
  end
  eq(items(3, 20), { { "Ana López", "Ana López", 17 } }) -- after the comma; Ana's already there
  eq(items(4, 8), { { "Bob Smith", "Bob Smith", 6 } })
  eq(items(6, 16), { { "Bob Smith", "@bob-smith", 12 } })
  eq(items(6, 4), {}) -- not after an @
  eq(items(1, 8), {}) -- title: isn't a people field
end

T["completion offers person: filters"] = function()
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose find tasks ", "cmdline"), "person:bob-smith"), true)
end

return T

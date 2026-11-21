local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  -- timestamps are covered in test_timestamps; here they'd only shift line numbers
  child.lua(
    ("require('logpose').setup(vim.tbl_extend('force', { root = %q, timestamps = { created = false, modified = false } }, %s))"):format(
      root,
      extra or "{}"
    )
  )
end

local function lines(...)
  return table.concat({ ... }, "\n") .. "\n"
end

local function d(iso)
  return root .. "/daily/daily-" .. iso .. ".md"
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      setup()
      H.freeze(child, 2026, 10, 14) -- Wednesday; the previous workday is Tuesday the 13th
      H.write(
        d("2026-10-13"),
        lines(
          "# 2026-10-13 daily notes",
          "",
          "## Notes",
          "",
          "- [x] review PR #acme",
          "- [ ] write ADR #acme",
          "  → [[tasks/adr|task]]",
          "- [ ] call bank",
          "met Ana about the cache",
          "",
          "## Blockers",
          "",
          "- waiting on VPN access"
        )
      )
      H.write(
        root .. "/tasks/flaky.md",
        lines(
          "---",
          'title: "Fix flaky test"',
          "status: in-progress",
          "project: acme",
          "blocked: waiting on CI runners",
          "---",
          "## Log",
          "",
          "- 2026-10-12 09:00: created in Backlog",
          "- 2026-10-13 10:00: Backlog → TODO",
          "- 2026-10-13 15:00: TODO → In progress"
        )
      )
      H.write(
        root .. "/tasks/ship.md",
        lines(
          "---",
          'title: "Ship the release"',
          "status: done",
          "project: acme",
          "done: 2026-10-13",
          "---",
          "## Log",
          "",
          "- 2026-10-13 17:00: In progress → Done"
        )
      )
      H.write(
        root .. "/tasks/docs.md",
        lines("---", 'title: "Write docs"', "status: todo", "project: thesis", "due: 2026-10-14", "---")
      )
      H.write(
        root .. "/tasks/old.md",
        lines("---", 'title: "Old work"', "status: done", "project: acme", "done: 2026-10-01", "---")
      )
      H.write(
        root .. "/meetings/acme/2026-10-13 - retro.md",
        lines("---", "type: retro", "date: 2026-10-13", 'title: "Retro"', "project: acme", "---")
      )
      H.write(
        root .. "/meetings/acme/2026-10-14 - planning.md",
        lines("---", "type: planning", "date: 2026-10-14", 'title: "Planning"', "project: acme", "---")
      )
    end,
    post_once = child.stop,
  },
})

local function collect()
  local s = child.lua_get(("require('logpose.standup').collect(%q)"):format(root))
  local function texts(list)
    return vim.tbl_map(function(e)
      return e.text .. (e.note and (" (" .. e.note .. ")") or "") .. (e.project and (" ◆ " .. e.project) or "")
    end, list)
  end
  return { since = s.since, yesterday = texts(s.yesterday), today = texts(s.today), blockers = texts(s.blockers) }
end

T["worked out from what happened since the previous workday"] = function()
  local s = collect()
  eq(s.since, "2026-10-13")
  eq(s.yesterday, {
    "Fix flaky test (Backlog → In progress) ◆ acme",
    "Retro (meeting) ◆ acme",
    "review PR #acme (to-do) ◆ acme",
    "Ship the release (In progress → Done) ◆ acme",
  })
  -- no note for today yet: what it will carry over is today's plan
  eq(s.today, {
    "Fix flaky test (In progress) ◆ acme",
    "Planning (meeting) ◆ acme",
    "write ADR #acme (to-do) ◆ acme",
    "Write docs (due today) ◆ thesis",
    "call bank (to-do)",
  })
  eq(s.blockers, { "Fix flaky test (waiting on CI runners) ◆ acme", "waiting on VPN access" })
end

T["a Monday looks back to Friday"] = function()
  H.freeze(child, 2026, 10, 19)
  H.write(
    root .. "/meetings/2026-10-16 - demo.md",
    lines("---", "type: adhoc", "date: 2026-10-16", 'title: "Demo"', "---")
  )
  local s = collect()
  eq(s.since, "2026-10-16")
  eq(s.yesterday, { "Demo (meeting)" })
end

T["the today screen shows it first; y copies it"] = function()
  child.cmd("Logpose today")
  local text = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(text, "## Standup\n\n### Yesterday · since Tue 13 Oct (4)")
  H.contains(text, "- [x] Ship the release  (In progress → Done)  ◆ acme")
  H.contains(text, "### Today (5)")
  H.contains(text, "### Blockers (2)")
  H.contains(text, "## Coming up")
  child.type_keys("y")
  local copied = child.fn.getreg('"')
  H.contains(copied, "# Standup 2026-10-14\n\n## Yesterday\n\n### acme\n\n- Fix flaky test (Backlog → In progress)")
  H.contains(copied, "### thesis\n\n- Write docs (due today)")
  H.contains(copied, "### other\n\n- call bank (to-do)")
end

T[":Logpose standup opens it on the today screen; ! copies; a date shows that day's"] = function()
  child.cmd("Logpose standup")
  eq(child.api.nvim_get_current_line(), "## Standup")
  child.cmd("Logpose standup!")
  H.contains(child.fn.getreg('"'), "# Standup 2026-10-14")
  child.cmd("Logpose standup 2026-10-13")
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "# Standup 2026-10-13")
end

T["flat without grouping"] = function()
  setup("{ standup = { group_by_project = false } }")
  child.cmd("Logpose standup!")
  local copied = child.fn.getreg('"')
  eq(copied:find("### ", 1, true), nil)
  H.contains(copied, "## Today\n\n- Fix flaky test (In progress)")
end

T["a new daily note"] = MiniTest.new_set()

-- today's meeting (in the fixtures), linked from the note made for the day
local planning = "- acme: [[meetings/acme/2026-10-14 - planning|Planning]]"
-- and the note before it, in the frontmatter
local previous = { "---", 'previous: "[[daily/daily-2026-10-13|Tue 2026-10-13]]"', "---" }

T["a new daily note"]["carries open to-dos (from anywhere in the note) and blockers"] = function()
  child.cmd("Logpose daily")
  eq(
    H.read(d("2026-10-14")),
    lines(
      previous[1],
      previous[2],
      previous[3],
      "# 2026-10-14 daily notes",
      "",
      "## To-dos",
      "",
      "- [ ] write ADR #acme",
      "  → [[tasks/adr|task]]",
      "- [ ] call bank",
      "",
      "## Blockers",
      "",
      "- waiting on VPN access",
      "",
      "## Meetings",
      "",
      planning,
      "",
      "## Notes"
    )
  )
  eq(child.api.nvim_win_get_cursor(0)[1], 22) -- under ## Notes, a blank line apart
  local prev = H.read(d("2026-10-13"))
  H.contains(prev, "- [x] review PR #acme\n- [>] write ADR #acme\n  → [[tasks/adr|task]]\n- [>] call bank")
  -- now today's note is the plan
  local s = collect()
  eq(s.blockers, { "Fix flaky test (waiting on CI runners) ◆ acme", "waiting on VPN access" })
end

T["a new daily note"]["carry_over = false and mark_carried = false"] = function()
  setup("{ daily = { carry_over = false } }")
  child.cmd("Logpose daily")
  eq(
    H.read(d("2026-10-14")),
    lines(
      previous[1],
      previous[2],
      previous[3],
      "# 2026-10-14 daily notes",
      "",
      "## Meetings",
      "",
      planning,
      "",
      "## Notes"
    )
  )
  vim.fn.delete(d("2026-10-14"))
  setup("{ daily = { mark_carried = false } }")
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), "- [ ] write ADR #acme")
  eq(H.read(d("2026-10-13")):find("[>]", 1, true), nil)
end

T["a new daily note"]["only today's carries: a note for another day leaves the to-dos where they are"] = function()
  child.cmd("Logpose daily 2026-10-15") -- tomorrow
  H.contains(H.read(d("2026-10-15")), "---\n# 2026-10-15 daily notes\n\n## Notes\n")
  child.cmd("Logpose daily 2026-10-12") -- the day before the last note
  H.contains(H.read(d("2026-10-12")), "---\n# 2026-10-12 daily notes\n\n## Notes\n")
  local prev = H.read(d("2026-10-13"))
  H.contains(prev, "- [ ] write ADR #acme")
  eq(prev:find("[>]", 1, true), nil)
  -- today's note still gets them
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), "## To-dos\n\n- [ ] write ADR #acme")
end

T["a new daily note"]["code blocks stay code; nested to-dos keep their nesting"] = function()
  H.write(
    d("2026-10-13"),
    lines(
      "# 2026-10-13 daily notes",
      "",
      "## Notes",
      "",
      "- [ ] release 1.2",
      "  - [ ] bump the version",
      "  - [x] changelog",
      "    - [ ] under a checked one",
      "- [x] done",
      "  - [ ] left open",
      "",
      "PR template:",
      "",
      "```markdown",
      "## Blockers",
      "- [ ] tests added",
      "```",
      "",
      "## Blockers",
      "",
      "- the staging VM",
      "",
      "```sh",
      "ssh staging",
      "",
      "uptime",
      "```"
    )
  )
  child.cmd("Logpose daily")
  local new = H.read(d("2026-10-14"))
  H.contains(
    new,
    lines(
      "## To-dos",
      "",
      "- [ ] release 1.2",
      "  - [ ] bump the version",
      "  - [ ] under a checked one",
      "- [ ] left open",
      "",
      "## Blockers",
      "",
      "- the staging VM",
      "",
      "```sh",
      "ssh staging",
      "",
      "uptime",
      "```",
      ""
    )
  )
  eq(new:find("tests added", 1, true), nil)
  local old = H.read(d("2026-10-13"))
  H.contains(old, "```markdown\n## Blockers\n- [ ] tests added\n```") -- the code block is untouched
  H.contains(old, "- [>] release 1.2\n  - [>] bump the version\n  - [x] changelog\n    - [>] under a checked one")
end

T["a new daily note"]["without a previous note: the template, and the day's meetings"] = function()
  vim.fn.delete(d("2026-10-13"))
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")), lines("# 2026-10-14 daily notes", "", "## Meetings", "", planning, "", "## Notes"))
end

return T

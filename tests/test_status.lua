local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  -- timestamps are covered in test_timestamps; here they'd only shift line numbers
  child.lua(
    ("require('logpose').setup(vim.tbl_deep_extend('force', { root = %q, timestamps = { created = false, modified = false } }, %s))"):format(
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

local function task(name, ...)
  H.write(root .. "/tasks/" .. name .. ".md", lines(...))
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
          "- [x] promoted and checked",
          "  → [[tasks/adr|task]]",
          "- [ ] call bank",
          "met Ana about the cache",
          "",
          "## Blockers",
          "",
          "- waiting on VPN access"
        )
      )
      task(
        "flaky",
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
      task(
        "ship",
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
      task("docs", "---", 'title: "Write docs"', "status: todo", "project: thesis", "due: 2026-10-14", "---")
      task("old", "---", 'title: "Old work"', "status: done", "project: acme", "done: 2026-10-01", "---")
      task("adr", "---", 'title: "Write the ADR"', "status: in-progress", "project: acme", "---")
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
  local s = child.lua_get(("require('logpose.notes.status').collect(%q)"):format(root))
  local function texts(list)
    return vim.tbl_map(function(e)
      return e.label .. " (" .. e.note .. ")" .. (e.project and (" ◆ " .. e.project) or "")
    end, list)
  end
  return { since = s.since, yesterday = texts(s.yesterday), today = texts(s.today), blockers = texts(s.blockers) }
end

-- The lines of today's note (2026-10-14) made from the fixtures.
local status = {
  yesterday = {
    "## Yesterday",
    "",
    "- acme: [[tasks/flaky|Fix flaky test]] — Backlog → In progress",
    "- acme: [[meetings/acme/2026-10-13 - retro|Retro]] — meeting",
    "- acme: [[daily/daily-2026-10-13|review PR]] — to-do done",
    "- acme: [[tasks/ship|Ship the release]] — In progress → Done",
  },
  today = {
    "## Today",
    "",
    "- acme: [[tasks/flaky|Fix flaky test]] — In progress",
    "- acme: [[tasks/adr|Write the ADR]] — In progress",
    "- thesis: [[tasks/docs|Write docs]] — TODO, due today",
  },
  blockers = {
    "## Blockers",
    "",
    "- waiting on VPN access",
    "- acme: [[tasks/flaky|Fix flaky test]] — waiting on CI runners",
  },
}
local planning = "- acme: [[meetings/acme/2026-10-14 - planning|Planning]]"
local previous = { "---", 'previous: "[[daily/daily-2026-10-13|Tue 2026-10-13]]"', "---" }

local function note(...)
  local out = vim.list_extend({}, previous)
  vim.list_extend(out, { "# 2026-10-14 daily notes" })
  for _, part in ipairs({ ... }) do
    table.insert(out, "")
    vim.list_extend(out, type(part) == "table" and part or { part })
  end
  return lines(unpack(out))
end

local function buf_text()
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

T["collect"] = MiniTest.new_set()

T["collect"]["worked out from what happened since the previous workday"] = function()
  local s = collect()
  eq(s.since, "2026-10-13")
  -- a to-do made into a task isn't listed: the task speaks for it
  eq(s.yesterday, {
    "Fix flaky test (Backlog → In progress) ◆ acme",
    "Retro (meeting) ◆ acme",
    "review PR (to-do done) ◆ acme",
    "Ship the release (In progress → Done) ◆ acme",
  })
  eq(s.today, {
    "Fix flaky test (In progress) ◆ acme",
    "Write the ADR (In progress) ◆ acme",
    "Write docs (TODO, due today) ◆ thesis",
  })
  eq(s.blockers, { "Fix flaky test (waiting on CI runners) ◆ acme" })
end

T["collect"]["a Monday looks back to Friday"] = function()
  H.freeze(child, 2026, 10, 19)
  H.write(
    root .. "/meetings/2026-10-16 - demo.md",
    lines("---", "type: adhoc", "date: 2026-10-16", 'title: "Demo"', "---")
  )
  local s = collect()
  eq(s.since, "2026-10-16")
  eq(s.yesterday, { "Demo (meeting)" })
end

T["collect"]["a task done today is in Today"] = function()
  task("quick", "---", 'title: "Quick fix"', "status: done", "done: 2026-10-14", "---")
  H.contains(table.concat(collect().today, "\n"), "Quick fix (→ Done)")
end

T["collect"]["only your tasks: someone else's stay out, unless only_mine = false"] = function()
  setup("{ me = '@emmanuel' }")
  -- Ana's: in progress, moved yesterday, blocked; yours by name: in progress
  task(
    "anas",
    "---",
    'title: "Ana\'s migration"',
    "status: in-progress",
    "assignee: Ana",
    "blocked: waiting on DBA",
    "---",
    "## Log",
    "",
    "- 2026-10-13 10:00: TODO → In progress"
  )
  task("mine", "---", 'title: "My review"', "status: in-progress", "assignee: emmanuel", "---")
  local s = collect()
  local all =
    table.concat(vim.list_extend(vim.list_extend(vim.list_extend({}, s.yesterday), s.today), s.blockers), "\n")
  eq(all:find("Ana's migration", 1, true), nil)
  H.contains(table.concat(s.today, "\n"), "My review (In progress)")
  H.contains(table.concat(s.today, "\n"), "Write the ADR (In progress)") -- nobody's: yours
  setup("{ me = '@emmanuel', daily = { status = { only_mine = false } } }")
  s = collect()
  H.contains(table.concat(s.yesterday, "\n"), "Ana's migration (TODO → In progress)")
  H.contains(table.concat(s.today, "\n"), "Ana's migration (In progress)")
  H.contains(table.concat(s.blockers, "\n"), "Ana's migration (waiting on DBA)")
end

T["collect"]["a to-do's text without tags, mentions, due dates and link markup"] = function()
  eq(
    child.lua_get(
      [==[require('logpose.notes.status').plain("ask @ana about [[notes/cache|the cache]] #acme #12 due:2026-10-20")]==]
    ),
    "ask ana about the cache #12"
  )
end

T["a new daily note"] = MiniTest.new_set()

T["a new daily note"]["has the status, the carried to-dos and the day's meetings"] = function()
  child.cmd("Logpose daily")
  eq(
    H.read(d("2026-10-14")),
    note(
      status.yesterday,
      status.today,
      { "## To-dos", "", "- [ ] write ADR #acme", "  → [[tasks/adr|task]]", "- [ ] call bank" },
      status.blockers,
      { "## Meetings", "", planning },
      "## Notes"
    )
  )
  eq(child.api.nvim_win_get_cursor(0)[1], 36) -- under ## Notes, a blank line apart
  eq(child.api.nvim_get_current_line(), "")
  local prev = H.read(d("2026-10-13"))
  H.contains(prev, "- [x] review PR #acme\n- [>] write ADR #acme\n  → [[tasks/adr|task]]")
  H.contains(prev, "- [>] call bank")
end

T["a new daily note"]["fills the headings its template has, where they are"] = function()
  H.write(
    root .. "/templates/daily.md",
    lines("# {date}", "", "## Notes", "", "{cursor}", "", "## Today", "", "- [ ] plan the day", "", "## Yesterday")
  )
  setup("{ daily = { carry_over = false } }")
  child.cmd("Logpose daily")
  local text = H.read(d("2026-10-14"))
  H.contains(
    text,
    lines(
      "## Today",
      "",
      "- [ ] plan the day",
      status.today[3],
      status.today[4],
      status.today[5],
      "",
      "## Blockers", -- after Today when there's no To-dos
      "",
      status.blockers[4],
      "",
      "## Yesterday",
      "",
      status.yesterday[3]
    )
  )
  eq(child.api.nvim_get_current_line(), "")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false)[child.api.nvim_win_get_cursor(0)[1] - 1], "## Notes")
end

T["a new daily note"]["for a past day: Yesterday only; for a day to come: nothing"] = function()
  child.cmd("Logpose daily 2026-10-15")
  H.contains(H.read(d("2026-10-15")), "---\n# 2026-10-15 daily notes\n\n## Notes\n")
  H.freeze(child, 2026, 10, 16)
  child.cmd("Logpose daily 2026-10-14")
  local text = H.read(d("2026-10-14"))
  H.contains(text, table.concat(status.yesterday, "\n"))
  eq(text:find("## Today", 1, true), nil)
  eq(text:find("## Blockers", 1, true), nil)
end

T["a new daily note"]["carries your blockers, not the ones logpose wrote"] = function()
  H.write(
    d("2026-10-13"),
    lines(
      "# 2026-10-13 daily notes",
      "",
      "## Blockers",
      "",
      "- waiting on VPN access",
      "- acme: [[tasks/old|Old work]] — waiting on review",
      "  - pinged Bob"
    )
  )
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), table.concat(status.blockers, "\n") .. "\n\n## Meetings")
end

T["a new daily note"]["daily.status.enabled = false leaves it out"] = function()
  setup("{ daily = { status = { enabled = false } } }")
  child.cmd("Logpose daily")
  eq(
    H.read(d("2026-10-14")),
    note(
      { "## To-dos", "", "- [ ] write ADR #acme", "  → [[tasks/adr|task]]", "- [ ] call bank" },
      { "## Blockers", "", "- waiting on VPN access" },
      { "## Meetings", "", planning },
      "## Notes"
    )
  )
  child.cmd("Logpose daily refresh")
  H.contains(child.notifications()[1].msg, "the status is off")
end

T["refresh"] = MiniTest.new_set()

local function make_note()
  child.cmd("Logpose daily")
  child.cmd("bwipeout!")
end

T["refresh"]["on opening today's note: tasks follow the board, your lines stay"] = function()
  make_note()
  local text = H.read(d("2026-10-14"))
  -- your edits: a line of your own, a sub-bullet, a generated line deleted, a label reworded
  text = text:gsub("(%- acme: %[%[tasks/flaky|Fix flaky test%]%] — In progress\n)", "%1  - should land after lunch\n")
  text = text:gsub("%- thesis: %[%[tasks/docs|Write docs%]%] — TODO, due today\n", "- pair with Ana\n")
  H.write(d("2026-10-14"), text)
  -- the board moves on: flaky is done and unblocked, a new task starts
  task(
    "flaky",
    "---",
    'title: "Fix flaky test"',
    "status: done",
    "project: acme",
    "done: 2026-10-14",
    "---",
    "## Log",
    "",
    "- 2026-10-13 15:00: TODO → In progress",
    "- 2026-10-14 11:00: In progress → Done"
  )
  task("cache", "---", 'title: "Cache layer"', "status: in-progress", "project: acme", "---")
  child.cmd("Logpose daily")
  local new = H.read(d("2026-10-14"))
  H.contains(
    new,
    lines(
      "## Today",
      "",
      "- acme: [[tasks/flaky|Fix flaky test]] — → Done",
      "  - should land after lunch",
      "- acme: [[tasks/adr|Write the ADR]] — In progress",
      "- pair with Ana",
      "- acme: [[tasks/cache|Cache layer]] — In progress",
      "- thesis: [[tasks/docs|Write docs]] — TODO, due today", -- deleted, back while it's still due
      "",
      "## To-dos"
    )
  )
  -- no longer blocked: its line goes; Yesterday stays as it was
  H.contains(new, "## Blockers\n\n- waiting on VPN access\n\n## Meetings")
  H.contains(new, table.concat(status.yesterday, "\n"))
  eq(buf_text() .. "\n", new) -- the buffer shows it
end

T["refresh"]["a resolved blocker you wrote under stays"] = function()
  make_note()
  local text = H.read(d("2026-10-14")):gsub("(— waiting on CI runners\n)", "%1  - asked infra\n")
  H.write(d("2026-10-14"), text)
  task("flaky", "---", 'title: "Fix flaky test"', "status: in-progress", "project: acme", "---")
  child.cmd("Logpose daily refresh")
  H.contains(H.read(d("2026-10-14")), "— waiting on CI runners\n  - asked infra\n")
  H.contains(child.notifications()[1].msg, "status already up to date")
end

T["refresh"]["an unsaved note is changed in its buffer, and u undoes it"] = function()
  child.cmd("Logpose daily")
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "", "typing…" })
  task("cache", "---", 'title: "Cache layer"', "status: in-progress", "project: acme", "---")
  child.cmd("Logpose daily refresh")
  H.contains(buf_text(), "[[tasks/cache|Cache layer]] — In progress")
  H.contains(buf_text(), "typing…")
  eq(H.read(d("2026-10-14")):find("Cache layer", 1, true), nil)
  eq(child.bo.modified, true)
  child.cmd("undo")
  eq(buf_text():find("Cache layer", 1, true), nil)
end

T["refresh"]["refresh! rebuilds Yesterday; in a past note it's all there is"] = function()
  make_note()
  local text = H.read(d("2026-10-14"))
  text = text:gsub("— Backlog → In progress", "— edited by hand")
  text = text:gsub("(%- acme: %[%[meetings/acme/2026%-10%-13 %- retro|Retro%]%] — meeting\n)", "%1- my own line\n")
  text = text:gsub("(\n## Today)", "\n- acme: [[tasks/old|Old work]] — never happened\n%1")
  H.write(d("2026-10-14"), text)
  child.cmd("Logpose daily refresh!")
  local new = H.read(d("2026-10-14"))
  H.contains(new, status.yesterday[3] .. "\n" .. status.yesterday[4] .. "\n- my own line\n")
  eq(new:find("never happened", 1, true), nil)

  H.freeze(child, 2026, 10, 15)
  child.cmd("edit " .. d("2026-10-14"))
  child.cmd("Logpose daily refresh")
  local n = #child.notifications()
  H.contains(child.notifications()[n].msg, "a past note's Today and Blockers stay as they were")
  child.cmd("Logpose daily refresh!")
  H.contains(child.notifications()[n + 1].msg, "status already up to date")
end

T["refresh"]["daily.status.refresh = 'manual' leaves the note as it is on opening"] = function()
  setup("{ daily = { status = { refresh = 'manual' } } }")
  make_note()
  task("cache", "---", 'title: "Cache layer"', "status: in-progress", "project: acme", "---")
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")):find("Cache layer", 1, true), nil)
  child.cmd("Logpose daily refresh")
  H.contains(H.read(d("2026-10-14")), "[[tasks/cache|Cache layer]] — In progress")
end

T["copy"] = MiniTest.new_set()

T["copy"]["the status as written, grouped by project"] = function()
  make_note()
  local text = H.read(d("2026-10-14")):gsub("(— Backlog → In progress\n)", "%1  - flaky on [[notes/ci|CI]]\n")
  H.write(d("2026-10-14"), text .. "\n")
  child.cmd("Logpose daily copy")
  eq(
    child.fn.getreg('"'),
    table.concat({
      "# Status 2026-10-14",
      "",
      "## Yesterday",
      "",
      "### acme",
      "",
      "- Fix flaky test (Backlog → In progress)",
      "  - flaky on CI",
      "- Retro (meeting)",
      "- review PR (to-do done)",
      "- Ship the release (In progress → Done)",
      "",
      "## Today",
      "",
      "### acme",
      "",
      "- Fix flaky test (In progress)",
      "- Write the ADR (In progress)", -- its to-do isn't listed again
      "",
      "### thesis",
      "",
      "- Write docs (TODO, due today)",
      "",
      "### other",
      "",
      "- call bank (to-do)",
      "",
      "## Blockers",
      "",
      "### acme",
      "",
      "- Fix flaky test (waiting on CI runners)",
      "",
      "### other",
      "",
      "- waiting on VPN access",
    }, "\n")
  )
end

T["copy"]["flat without grouping"] = function()
  setup("{ daily = { status = { group_by_project = false } } }")
  child.cmd("Logpose daily copy") -- makes today's note
  local copied = child.fn.getreg('"')
  eq(copied:find("### ", 1, true), nil)
  H.contains(copied, "## Today\n\n- Fix flaky test (In progress)\n")
  H.contains(H.read(d("2026-10-14")), "## Yesterday")
end

T["the today screen has no standup; y copies the status"] = function()
  child.cmd("Logpose today")
  local text = buf_text()
  eq(text:find("Standup", 1, true), nil)
  H.contains(text, "### Due soon (1)\n\n- Write docs  (due today)  ◆ thesis")
  child.type_keys("y")
  H.contains(child.fn.getreg('"'), "# Status 2026-10-14")
end

T["carrying over"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      setup("{ daily = { status = { enabled = false } } }")
    end,
  },
})

T["carrying over"]["carry_over = false and mark_carried = false"] = function()
  setup("{ daily = { carry_over = false, status = { enabled = false } } }")
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")), note({ "## Meetings", "", planning }, "## Notes"))
  vim.fn.delete(d("2026-10-14"))
  setup("{ daily = { carry_over = true, mark_carried = false, status = { enabled = false } } }")
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), "- [ ] write ADR #acme")
  eq(H.read(d("2026-10-13")):find("[>]", 1, true), nil)
end

T["carrying over"]["only today's carries: a note for another day leaves the to-dos where they are"] = function()
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

T["carrying over"]["code blocks stay code; nested to-dos keep their nesting"] = function()
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

T["carrying over"]["without a previous note: the template, and the day's meetings"] = function()
  vim.fn.delete(d("2026-10-13"))
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")), lines("# 2026-10-14 daily notes", "", "## Meetings", "", planning, "", "## Notes"))
end

return T

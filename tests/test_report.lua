local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local SPRINTS = "{ period = { kind = 'sprint', sprint = { anchor = '2026-10-01', first_number = 42 } } }"

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      setup(SPRINTS)
      H.freeze(child, 2026, 10, 14)
      H.write(
        root .. "/tasks/shipped-login.md",
        '---\ntitle: "Shipped login"\nstatus: done\nproject: acme\ndone: 2026-10-13\n---\n'
      )
      H.write(
        root .. "/tasks/archive/sprint-41/old-fix.md",
        '---\ntitle: "Old fix"\nstatus: done\ndone: 2026-09-25\n---\n'
      )
      H.write(
        root .. "/meetings/acme/2026-10-07 - retro.md",
        '---\ntype: retro\ndate: 2026-10-07\nproject: acme\ntitle: "Retro"\n---\n# Retro\n## Decisions\n- Use Postgres\n## Action items\n- [ ] write ADR @ana due:2026-10-10\n'
      )
      H.write(
        root .. "/meetings/2026-09-20 - planning.md",
        '---\ntype: planning\ndate: 2026-09-20\ntitle: "Planning"\n---\n# Planning\n- [ ] stale thing\n'
      )
      H.write(root .. "/daily/daily-2026-09-25.md", "# 2026-09-25\n\n- [ ] old capture\n")
    end,
    post_once = child.stop,
  },
})

local function report(args)
  child.cmd("Logpose report" .. (args and (" " .. args) or ""))
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

T["current sprint report with review"] = function()
  local r = report()
  H.contains(r, "# Report: sprint-42 (2026-10-01 – 2026-10-14)\n\nGenerated 2026-10-14.")
  H.contains(r, "## Done tasks (1)\n\n### 2026-10-13\n\n- Shipped login ([[tasks/shipped-login|Shipped login]])  @acme")
  H.contains(r, "## Meetings (1)\n\n### retro\n\n- 2026-10-07 [[meetings/acme/2026-10-07 - retro|Retro]]  @acme")
  H.contains(r, "## Decisions (1)\n\n- Use Postgres ([[meetings/acme/2026-10-07 - retro|Retro]])")
  H.contains(r, "## Open action items (1)\n\n- [ ] write ADR @ana due:2026-10-10 (")
  H.contains(r, "### Overdue actions (1)\n\n- [acme] write ADR @ana due:2026-10-10 (due 2026-10-10 @ana)")
  H.contains(r, "### Open to-dos older than 14 days (2)\n")
  H.contains(r, "- 2026-09-20 stale thing (")
  H.contains(r, "- 2026-09-25 old capture (")
  H.contains(child.api.nvim_buf_get_name(0), "logpose://report/sprint-42")
end

T["previous sprint"] = function()
  local r = report("sprint -1")
  H.contains(r, "# Report: sprint-41 (2026-09-17 – 2026-09-30)")
  H.contains(r, "## Done tasks (1)\n\n### 2026-09-25\n\n- Old fix (")
  H.contains(r, "## Meetings (1)\n\n### planning\n\n- 2026-09-20 [[meetings/2026-09-20 - planning|Planning]]")
  H.contains(r, "## Open action items (1)\n\n- [ ] stale thing")
end

T["project filter"] = function()
  local r = report("project:acme")
  H.contains(r, "# Report: sprint-42 (2026-10-01 – 2026-10-14) — project:acme")
  H.contains(r, "### Open to-dos older than 14 days (0)")
end

T["weekly report and offsets"] = function()
  setup()
  H.contains(report(), "# Report: week of 2026-10-12")
  child.cmd("close")
  H.contains(report("week -1"), "# Report: week of 2026-10-05")
  child.cmd("close")
  H.contains(report("week 2026-09-22"), "# Report: week of 2026-09-21")
  child.cmd("Logpose report week 3")
  H.contains(child.notifications()[1].msg, "need a sign")
end

T["! saves the report"] = function()
  child.cmd("Logpose report! sprint 41")
  local path = root .. "/reports/sprint-41.md"
  eq(child.api.nvim_buf_get_name(0), path)
  H.contains(H.read(path), "# Report: sprint-41")
end

return T

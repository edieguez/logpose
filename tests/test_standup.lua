local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      setup()
      H.freeze(child, 2026, 10, 14) -- Wednesday; no note for Tuesday
    end,
    post_once = child.stop,
  },
})

local function lines(...)
  return table.concat({ ... }, "\n") .. "\n"
end

local function d(iso)
  return root .. "/daily/daily-" .. iso .. ".md"
end

local PREV = lines(
  "# 2026-10-12 daily notes",
  "",
  "## Yesterday",
  "",
  "## Today",
  "- [x] review PR #acme",
  "- [ ] fix flaky test #acme",
  "- [ ] write thesis chapter #thesis",
  "- [>] old migrated",
  "- [ ] ",
  "Paired with Ana on CI",
  "",
  "## Blockers",
  "- waiting on infra",
  "",
  "## Meetings",
  "",
  "## Notes"
)

T["a new daily note starts from the previous one"] = function()
  H.write(d("2026-10-12"), PREV)
  child.cmd("Logpose daily")
  eq(
    H.read(d("2026-10-14")),
    lines(
      "# 2026-10-14 daily notes",
      "",
      "## Yesterday",
      "",
      "- review PR #acme",
      "Paired with Ana on CI",
      "",
      "## Today",
      "",
      "- [ ] fix flaky test #acme",
      "- [ ] write thesis chapter #thesis",
      "",
      "## Blockers",
      "",
      "## Meetings",
      "",
      "## Notes"
    )
  )
  eq(child.api.nvim_win_get_cursor(0), { 12, 0 }) -- the empty line after the carried tasks
  local prev = H.read(d("2026-10-12"))
  H.contains(prev, "- [>] fix flaky test #acme\n- [>] write thesis chapter #thesis\n")
  H.contains(prev, "- [x] review PR #acme\n")
end

T["carried tasks are only listed once by search"] = function()
  H.write(d("2026-10-12"), PREV)
  child.cmd("Logpose daily")
  child.lua([[vim.ui.select = function(items, opts, cb) _G.labels = vim.tbl_map(opts.format_item, items); cb(nil) end]])
  setup("{ picker = 'select' }")
  child.cmd("Logpose find tasks open #acme")
  eq(#child.lua_get("_G.labels"), 1)
end

T["carry_forward = false only fills Yesterday"] = function()
  setup("{ standup = { carry_forward = false } }")
  H.write(d("2026-10-12"), PREV)
  child.cmd("Logpose daily")
  local new = H.read(d("2026-10-14"))
  H.contains(new, "## Yesterday\n\n- review PR #acme\nPaired with Ana on CI\n\n## Today\n\n## Blockers")
  eq(H.read(d("2026-10-12")), PREV)
end

T["mark_carried = false leaves the previous note alone"] = function()
  setup("{ standup = { mark_carried = false } }")
  H.write(d("2026-10-12"), PREV)
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), "## Today\n\n- [ ] fix flaky test #acme\n")
  eq(H.read(d("2026-10-12")), PREV)
end

T["include_done adds yesterday's DONE entries without duplicates"] = function()
  setup("{ standup = { include_done = true } }")
  H.write(d("2026-10-12"), PREV)
  H.write(
    root .. "/DONE.md",
    lines(
      "# DONE",
      "",
      "## 2026-10-12",
      "- [x] shipped release ([[meetings/x|x]])",
      "- [x] review PR #acme",
      "",
      "## 2026-10-13",
      "- [x] other day"
    )
  )
  child.cmd("Logpose daily")
  H.contains(
    H.read(d("2026-10-14")),
    "## Yesterday\n\n- review PR #acme\nPaired with Ana on CI\n- shipped release ([[meetings/x|x]])\n\n## Today"
  )
end

T["no previous note leaves the template as is"] = function()
  child.cmd("Logpose daily")
  H.contains(H.read(d("2026-10-14")), "## Yesterday\n\n## Today\n\n## Blockers")
end

T["an existing daily note is never changed"] = function()
  H.write(d("2026-10-12"), PREV)
  H.write(d("2026-10-14"), "# mine\n")
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")), "# mine\n")
  eq(H.read(d("2026-10-12")), PREV)
end

T["custom section names"] = function()
  setup("{ standup = { sections = { yesterday = 'Ayer', today = 'Hoy', blockers = 'Bloqueos' } } }")
  H.write(root .. "/templates/daily.md", "# {date}\n\n## Ayer\n\n## Hoy\n{cursor}\n\n## Bloqueos\n")
  H.write(d("2026-10-12"), "# x\n\n## Hoy\n- [x] hecho\n- [ ] pendiente\n")
  child.cmd("Logpose daily")
  eq(H.read(d("2026-10-14")), "# 2026-10-14\n\n## Ayer\n\n- hecho\n\n## Hoy\n\n- [ ] pendiente\n\n## Bloqueos\n")
end

T[":Logpose standup"] = MiniTest.new_set()

local function standup()
  child.cmd("Logpose standup")
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

T[":Logpose standup"]["groups today's sections by project"] = function()
  vim.fn.mkdir(root .. "/meetings/acme", "p")
  vim.fn.mkdir(root .. "/meetings/thesis", "p")
  H.write(d("2026-10-12"), PREV)
  child.cmd("Logpose daily")
  eq(standup(), {
    "# Standup 2026-10-14",
    "",
    "## Yesterday",
    "",
    "### acme",
    "",
    "- review PR #acme",
    "",
    "### other",
    "",
    "Paired with Ana on CI",
    "",
    "## Today",
    "",
    "### acme",
    "",
    "- [ ] fix flaky test #acme",
    "",
    "### thesis",
    "",
    "- [ ] write thesis chapter #thesis",
    "",
    "## Blockers",
    "",
    "- (none)",
  })
  H.contains(child.api.nvim_buf_get_name(0), "logpose://standup/2026-10-14")
end

T[":Logpose standup"]["flat without projects or with grouping off"] = function()
  H.write(d("2026-10-14"), lines("# d", "## Yesterday", "- did a #x", "## Today", "- [ ] b", "## Blockers", "- infra"))
  local out = standup()
  eq(vim.list_slice(out, 3, 5), { "## Yesterday", "", "- did a #x" })
  vim.fn.mkdir(root .. "/meetings/x", "p")
  setup("{ standup = { group_by_project = false } }")
  child.cmd("close")
  eq(vim.list_slice(standup(), 3, 5), { "## Yesterday", "", "- did a #x" })
end

T[":Logpose standup"]["uses unsaved edits of the daily note"] = function()
  child.cmd("Logpose daily")
  child.api.nvim_buf_set_lines(0, 5, 6, false, { "- [ ] typed, not saved" })
  H.contains(table.concat(standup(), "\n"), "## Today\n\n- [ ] typed, not saved")
end

T[":Logpose standup"]["needs today's daily note"] = function()
  child.cmd("Logpose standup")
  H.contains(child.notifications()[1].msg, "no daily note for 2026-10-14")
end

return T

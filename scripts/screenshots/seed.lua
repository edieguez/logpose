-- Builds the demo journal used for the README screenshots, through logpose itself where it can.
local root = _G.ROOT
vim.cmd("runtime plugin/logpose.lua")
require("logpose").setup({
  root = root,
  picker = "select",
  me = "@emmanuel",
  period = { kind = "sprint", sprint = { anchor = "2026-10-15", first_number = 43 } },
})
local function at(day)
  require("logpose.util.date")._now = function()
    return os.time({ year = 2026, month = 10, day = day, hour = 10, min = 30 })
  end
end
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end
local function insert_after(heading, lines)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l == heading then
      vim.api.nvim_buf_set_lines(0, i, i + 1, false, lines)
      return
    end
  end
end

-- name, status, project, extra frontmatter, title, day created
local tasks = {
  { "api-rate-limits", "backlog", "acme", "tags: [api]\n", "Design API rate limits", 8 },
  { "related-work", "backlog", "thesis", "", "Survey related work", 12 },
  { "flaky-test", "todo", "acme", "tags: [ci]\ndue: 2026-10-20\n", "Fix flaky checkout test", 14 },
  { "upgrade-pg", "todo", "acme", "", "Upgrade Postgres to 17", 15 },
  { "search-index", "in-progress", "acme", "tags: [perf]\n", "Speed up search indexing", 13 },
  { "chapter-3", "in-progress", "thesis", "due: 2026-10-16\n", "Write chapter 3 draft", 9 },
  { "vendor-sso", "follow-up", "acme", "blocked: waiting on Ana\n", "Vendor SSO integration", 6 },
  { "release-notes", "done", "acme", "done: 2026-10-15\n", "Publish 2.4 release notes", 10 },
}
write(root .. "/.logpose", "")
write(
  root .. "/projects/acme.md",
  '---\ntitle: "Acme API"\ntype: project\nproject: acme\ndescription: Payments API for the Acme storefront\npaths: [~/work/acme-api]\ncolor: "#e0af68"\ncreated: 2026-09-01T09:00\n---\n## Overview\n'
)
write(
  root .. "/projects/thesis.md",
  '---\ntitle: "Master\'s thesis"\ntype: project\nproject: thesis\ncreated: 2026-08-20T09:00\n---\n## Overview\n'
)
write(
  root .. "/projects/legacy-billing.md",
  '---\ntitle: "Legacy billing"\ntype: project\nproject: legacy-billing\narchived: true\ncreated: 2026-03-02T09:00\n---\n## Overview\n'
)
write(
  root .. "/tasks/billing.md",
  '---\ntitle: "Billing cleanup"\nstatus: done\nproject: legacy-billing\ndone: 2026-08-01\n---\n'
)
for _, t in ipairs(tasks) do
  write(
    ("%s/tasks/%s.md"):format(root, t[1]),
    ('---\ntitle: "%s"\nstatus: %s\nproject: %s\n%screated: 2026-10-%02dT09:00\n---\n## Context\n\n## Log\n\n- 2026-10-%02d 09:00: created in Backlog\n'):format(
      t[5],
      t[2],
      t[3],
      t[4],
      t[6],
      t[6]
    )
  )
end

vim.cmd("cd " .. root)
at(14)
vim.cmd("Logpose daily")
insert_after("## Today", {
  "",
  "- [x] Review Ana's PR on the cache layer #acme",
  "- [x] Send thesis outline to advisor #thesis",
  "- [ ] Reproduce flaky checkout test #acme, see [[flaky-test]]",
  "",
})
vim.cmd("silent write")
vim.cmd("Logpose project acme")
vim.cmd("Logpose meeting retro")
insert_after("## Action items", {
  "",
  "- [ ] Add retries to the payment client @emmanuel due:2026-10-13",
  "- [ ] Share load-test results @ana due:2026-10-21",
})
insert_after("## To improve", { "", "- [[flaky-test]] fails on retries; [[vendor-sso]] waits on Ana's keys" })
vim.cmd("silent write")
at(15)
vim.cmd("Logpose meeting planning")
vim.cmd("silent write")
vim.cmd("Logpose project none")
vim.cmd("Logpose daily")
vim.cmd("silent write")

-- Earlier meetings, for :Logpose meetings.
for _, m in ipairs({
  {
    "acme/2026-10-07 - refinement",
    'type: refinement\ndate: 2026-10-07\nproject: acme\ntitle: "Refinement"\nattendees: [Ana López, Luis Pérez, Carla Gómez]',
    "- [ ] Split the search epic @luis\n- [x] Estimate SSO\n",
  },
  {
    "thesis/2026-10-09 - 1-1-dr-ruiz",
    'type: 1on1\ndate: 2026-10-09\nproject: thesis\ntitle: "1:1 Dr. Ruiz"\nwith: Dr. Ruiz\nattendees: [Dr. Ruiz]',
    "- [ ] Rewrite chapter 2 intro\n",
  },
  {
    "2026-10-12 - sync-with-qa",
    'type: adhoc\ndate: 2026-10-12\ntitle: "Sync with QA"\nattendees: [Marta, Ana López]',
    "",
  },
  {
    "acme/2026-10-01 - sprint-review",
    'type: review\ndate: 2026-10-01\nproject: acme\ntitle: "Sprint review"\nattendees: [Ana López, Luis Pérez, Marta, Jorge]',
    "- [x] Demo the new checkout\n",
  },
}) do
  write(("%s/meetings/%s.md"):format(root, m[1]), ("---\n%s\n---\n## Notes\n\n%s"):format(m[2], m[3]))
end

-- When notes were last edited, for the today screen's "Recently edited".
write(
  root .. "/notes/cache-design.md",
  '---\ntitle: "Cache design"\nproject: acme\ntags: [arch]\ncreated: 2026-10-12T16:00\n---\nSee [[search-index]].\n'
)
local uv = vim.uv or vim.loop
local now = os.time()
for path, ago in pairs({
  ["notes/cache-design.md"] = 2 * 3600,
  ["daily/daily-2026-10-14.md"] = 20 * 3600,
  ["meetings/acme/2026-10-14 - retro.md"] = 26 * 3600,
  ["meetings/acme/2026-10-15 - sprint-planning.md"] = 40 * 60,
  ["meetings/acme/2026-10-07 - refinement.md"] = 8 * 86400,
  ["meetings/thesis/2026-10-09 - 1-1-dr-ruiz.md"] = 6 * 86400,
  ["meetings/2026-10-12 - sync-with-qa.md"] = 3 * 86400,
  ["meetings/acme/2026-10-01 - sprint-review.md"] = 14 * 86400,
}) do
  uv.fs_utime(root .. "/" .. path, now - ago, now - ago)
end

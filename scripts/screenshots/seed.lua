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
  '---\ntitle: "Acme API"\ntype: project\nproject: acme\ndescription: Payments API for the Acme storefront\npaths: [~/work/acme-api]\ncolor: "#e0af68"\n---\n## Overview\n'
)
write(
  root .. "/projects/thesis.md",
  '---\ntitle: "Master\'s thesis"\ntype: project\nproject: thesis\n---\n## Overview\n'
)
write(
  root .. "/projects/legacy-billing.md",
  '---\ntitle: "Legacy billing"\ntype: project\nproject: legacy-billing\narchived: true\n---\n## Overview\n'
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

-- When notes were last edited, for the today screen's "Recently edited".
write(root .. "/notes/cache-design.md", "# Cache design\n\nSee [[search-index]].\n")
local uv = vim.uv or vim.loop
local now = os.time()
for path, ago in pairs({
  ["notes/cache-design.md"] = 2 * 3600,
  ["daily/daily-2026-10-14.md"] = 20 * 3600,
  ["meetings/acme/2026-10-14 - retro.md"] = 26 * 3600,
  ["meetings/acme/2026-10-15 - sprint-planning.md"] = 40 * 60,
}) do
  uv.fs_utime(root .. "/" .. path, now - ago, now - ago)
end

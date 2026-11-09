local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root, page

local PAGE =
  '---\ntitle: "Acme API"\ntype: project\nproject: acme\nmodified: 2026-11-01T09:00\n---\n## Overview\n\nPayments.\n'

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 11, 9)
      page = root .. "/projects/acme.md"
      H.write(page, PAGE)
    end,
    post_once = child.stop,
  },
})

local function seed()
  H.write(
    root .. "/projects/acme/use-postgres.md",
    '---\ntitle: "Use Postgres"\ntype: decision\nproject: acme\nstatus: accepted\n---\n'
  )
  H.write(root .. "/projects/acme/billing-api.md", '---\ntitle: "Billing API"\ntype: spec\nproject: acme\n---\n')
  H.write(
    root .. "/projects/acme/add-indexes.md",
    '---\ntitle: "Add indexes"\ntype: decision\nproject: acme\nstatus: proposed\n---\n'
  )
  H.write(root .. "/notes/queue.md", '---\ntitle: "Queue design"\nproject: acme\n---\n')
  H.write(root .. "/notes/postgres-tips.md", '---\ntitle: "Postgres tips"\n---\nlearnt on [[projects/acme|Acme]]\n')
  H.write(root .. "/notes/other.md", '---\ntitle: "Unrelated"\n---\n')
  for _, d in ipairs({ "2026-10-20", "2026-10-27", "2026-11-03", "2026-11-06" }) do
    H.write(
      root .. "/meetings/acme/" .. d .. " - retro.md",
      ('---\ntype: retro\ndate: %s\ntitle: "Retro"\nproject: acme\n---\n'):format(d)
    )
  end
end

local SECTION = table.concat({
  "## In this project",
  "",
  "<!-- logpose:hub -->",
  "- Decisions",
  "  - [[projects/acme/add-indexes|Add indexes]] · proposed",
  "  - [[projects/acme/use-postgres|Use Postgres]] · accepted",
  "- Specs",
  "  - [[projects/acme/billing-api|Billing API]]",
  "- Notes",
  "  - [[notes/postgres-tips|Postgres tips]]",
  "  - [[notes/queue|Queue design]]",
  "- Meetings (4)",
  "  - [[meetings/acme/2026-11-06 - retro|Retro]] · Fri 6 Nov",
  "  - [[meetings/acme/2026-11-03 - retro|Retro]] · Tue 3 Nov",
  "  - [[meetings/acme/2026-10-27 - retro|Retro]] · Tue 27 Oct",
  "<!-- /logpose:hub -->",
}, "\n")

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

T[":Logpose hub lists the project's docs, notes and latest meetings at the end of its page"] = function()
  seed()
  child.cmd("Logpose hub acme")
  H.contains(last_msg(), "updated the hub of acme")
  local text = H.read(page)
  eq(text, PAGE .. "\n" .. SECTION .. "\n")
  H.contains(text, "modified: 2026-11-01T09:00") -- not your edit
  -- again: nothing changes
  local before = vim.uv.fs_stat(page).mtime
  child.cmd("Logpose hub acme")
  H.contains(last_msg(), "the hub of acme is up to date")
  eq(vim.uv.fs_stat(page).mtime, before)
end

T["the section is replaced where it is; what's after it stays"] = function()
  seed()
  H.write(
    page,
    PAGE .. "\n## In this project\n\n<!-- logpose:hub -->\n- old\n<!-- /logpose:hub -->\n\n## Later\n\nmine\n"
  )
  child.cmd("Logpose hub acme")
  local text = H.read(page)
  H.contains(text, "<!-- logpose:hub -->\n- Decisions")
  H.contains(text, "<!-- /logpose:hub -->\n\n## Later\n\nmine\n")
  eq(text:find("- old", 1, true), nil)
end

T["it follows the journal on its own; a page being edited waits"] = function()
  seed()
  child.cmd("Logpose hub acme")
  child.lua(
    ([[require("logpose.notes.doc").create(%q, { type = "runbook", title = "Deploy", project = "acme" })]]):format(root)
  )
  child.lua(
    "local p = ...; vim.wait(1000, function() return io.open(p, 'r'):read('*a'):find('Runbooks', 1, true) ~= nil end, 50)",
    { page }
  )
  H.contains(H.read(page), "- Runbooks\n  - [[projects/acme/deploy|Deploy]]")
  -- unsaved changes in the page: left alone
  child.cmd("edit " .. page)
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "typing" })
  child.lua(
    ([[require("logpose.notes.doc").create(%q, { type = "spec", title = "Webhooks", project = "acme" })]]):format(root)
  )
  child.lua("vim.wait(600)")
  eq(H.read(page):find("Webhooks", 1, true), nil)
  eq(child.lua_get(("require('logpose.projects.hub').update(%q, 'acme')"):format(root)), "busy")
  child.cmd("write")
  child.lua(
    "local p = ...; vim.wait(1000, function() return io.open(p, 'r'):read('*a'):find('Webhooks', 1, true) ~= nil end, 50)",
    { page }
  )
  H.contains(H.read(page), "[[projects/acme/webhooks|Webhooks]]")
end

T["a project with nothing to list gets no section; projects.hub = false turns it off"] = function()
  child.cmd("Logpose hub acme")
  H.contains(last_msg(), "nothing to list for acme yet")
  eq(H.read(page), PAGE)
  child.lua(("require('logpose').setup({ root = %q, projects = { hub = false } })"):format(root))
  seed()
  child.lua("require('logpose.index').clear_cache()")
  child.lua("vim.wait(600)")
  eq(H.read(page), PAGE)
  -- by hand it still works
  child.cmd("Logpose hub! ")
  H.contains(last_msg(), "updated the hub of acme")
  H.contains(H.read(page), "<!-- logpose:hub -->")
end

return T

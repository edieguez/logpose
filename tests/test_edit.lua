local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
    end,
    post_once = child.stop,
  },
})

local TASK = "---\n"
  .. 'title: "Fix flaky test"\n'
  .. "status: todo\nproject: acme\ntags: [ci]\ndue:\nblocked:\n"
  .. "created: 2026-10-14T09:00\nmodified: 2026-10-14T09:00\n---\n"
  .. "## Context\n\n## Log\n\n- 2026-10-14 09:00: created in Backlog\n"

local function form()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- Replace the form line that starts with `key:`.
local function set(key, value)
  child.lua(([[(function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:match('^' .. %q .. ':') then lines[i] = %q end
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end)()]]):format(key, key .. ": " .. value))
end

local function edit(path)
  child.cmd("edit " .. path)
  child.cmd("Logpose edit")
end

T["the form shows the note's fields, with logpose's own as comments"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  eq(child.bo.filetype, "logpose-edit")
  eq(form(), {
    "title: Fix flaky test",
    "status: todo",
    "project: acme",
    "tags: ci",
    "due: ",
    "blocked: ",
    "",
    "# created: 2026-10-14T09:00",
    "# modified: 2026-10-14T09:00",
  })
  eq(child.api.nvim_win_get_config(0).relative, "editor") -- a float
end

T["saving a task goes through the board's logic"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  edit(root .. "/tasks/fix.md")
  set("title", "Fix the flaky checkout test")
  set("status", "In progress") -- a column label works too
  set("project", "Thesis Work")
  set("tags", "ci, #flaky")
  set("due", "+3d")
  set("blocked", "waiting on Ana")
  child.cmd("write")
  eq(child.bo.filetype, "markdown") -- the form closed
  local text = H.read(root .. "/tasks/fix.md")
  H.contains(text, 'title: "Fix the flaky checkout test"')
  H.contains(text, "status: in-progress")
  H.contains(text, "project: thesis-work")
  H.contains(text, "tags: [ci, flaky]")
  H.contains(text, "due: 2026-10-18")
  H.contains(text, "blocked: waiting on Ana")
  H.contains(text, "started: 2026-10-15")
  H.contains(text, "TODO → In progress")
  H.contains(text, "project: acme → thesis-work")
  H.contains(child.notifications()[#child.notifications()].msg, "updated")
  -- and the open buffer shows it
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "status: in-progress")
end

T["clearing a value and bad input"] = function()
  H.write(root .. "/tasks/fix.md", TASK:gsub("due:\n", "due: 2026-10-20\n"))
  edit(root .. "/tasks/fix.md")
  set("due", "")
  child.cmd("write")
  H.contains(H.read(root .. "/tasks/fix.md"), "\ndue:\n")
  edit(root .. "/tasks/fix.md")
  set("status", "nope")
  child.cmd("write")
  H.contains(child.notifications()[#child.notifications()].msg, 'unknown status "nope"')
  eq(child.bo.filetype, "logpose-edit") -- still open, nothing lost
  set("status", "todo")
  set("due", "someday")
  child.cmd("write")
  H.contains(child.notifications()[#child.notifications()].msg, "isn't a date")
  child.type_keys("q")
  eq(child.bo.filetype, "markdown")
  H.contains(H.read(root .. "/tasks/fix.md"), "status: todo")
end

T["moving a meeting to another project moves the note and fixes links"] = function()
  local old = root .. "/meetings/acme/2026-10-14 - retro.md"
  H.write(
    old,
    '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\nattendees: [Ana, Luis]\n'
      .. "series: acme/retro\n---\n## Notes\n"
  )
  H.write(
    root .. "/daily/daily-2026-10-14.md",
    "# 2026-10-14 daily notes\n\n## Meetings\n\n- acme: [[meetings/acme/2026-10-14 - retro|Retro]]\n"
  )
  edit(old)
  set("project", "web")
  set("attendees", "Ana, Maria")
  child.cmd("write")
  local new = root .. "/meetings/web/2026-10-14 - retro.md"
  eq(vim.fn.filereadable(old), 0)
  eq(vim.fn.isdirectory(root .. "/meetings/acme"), 0)
  local text = H.read(new)
  H.contains(text, "project: web")
  H.contains(text, "series: web/retro")
  H.contains(text, "attendees: [Ana, Maria]")
  H.contains(H.read(root .. "/daily/daily-2026-10-14.md"), "- web: [[meetings/web/2026-10-14 - retro|Retro]]")
  eq(child.api.nvim_buf_get_name(0), new)
end

T["completion offers what fits each field"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  H.write(root .. "/tasks/other.md", "---\ntitle: other\nstatus: todo\nproject: thesis\ntags: [perf]\n---\n")
  H.write(
    root .. "/meetings/x.md",
    '---\ntype: retro\ndate: 2026-10-01\ntitle: "R"\nattendees: [Ana, Luis]\n---\n## Notes\n'
  )
  H.write(root .. "/projects/thesis.md", '---\ntitle: "Master thesis"\nproject: thesis\n---\n')
  edit(root .. "/tasks/fix.md")
  local function words(line, col)
    child.api.nvim_buf_set_lines(0, 0, 1, false, { line })
    child.api.nvim_win_set_cursor(0, { 1, col or #line })
    local start = child.lua_get("require('logpose.edit').omnifunc(1, '')")
    local items = child.lua_get("require('logpose.edit').omnifunc(0, '')")
    return start, vim.tbl_map(function(i)
      return i.word
    end, items)
  end
  local start, w = words("project: th")
  eq({ start, w }, { 9, { "thesis" } })
  _, w = words("status: in")
  eq(w, { "in-progress" })
  start, w = words("tags: ci, p") -- the last item of a list, without the ones already there
  eq({ start, w }, { 10, { "perf" } })
  _, w = words("due: ")
  eq(w[1], "2026-10-15")
  eq(#w, 14)
  _, w = words("des", 3) -- a field name the form doesn't have yet
  eq(w, { "description: " })
  _, w = words("bl", 2) -- one it already has isn't offered again
  eq(w, {})
  local _, people = words("attendees: ")
  eq(people, { "Ana", "Luis" })
end

T["e on the board edits the card, and u undoes it"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  child.cmd("Logpose board")
  child.type_keys("l", "e") -- the card is in TODO
  eq(child.bo.filetype, "logpose-edit")
  set("project", "thesis")
  child.cmd("write")
  eq(child.bo.filetype, "logpose-board")
  H.contains(H.read(root .. "/tasks/fix.md"), "project: thesis")
  child.type_keys("u")
  H.contains(H.read(root .. "/tasks/fix.md"), "project: acme")
end

T["e in the projects manager edits the project page"] = function()
  H.write(root .. "/tasks/fix.md", TASK)
  child.cmd("Logpose projects")
  child.fn.search("acme")
  child.type_keys("e")
  eq(child.bo.filetype, "logpose-edit")
  H.contains(table.concat(form(), "\n"), "paths: ")
  set("title", "Acme API")
  set("description", "Payments")
  child.cmd("write")
  eq(child.bo.filetype, "logpose-projects")
  local page = H.read(root .. "/projects/acme.md")
  H.contains(page, 'title: "Acme API"')
  H.contains(page, "description: Payments")
  H.contains(table.concat(form(), "\n"), "Acme API")
  -- renaming a project belongs to R
  child.type_keys("e")
  set("project", "other")
  child.cmd("write")
  H.contains(child.notifications()[#child.notifications()].msg, "rename a project with R")
end

T[":Logpose edit outside the journal says so"] = function()
  child.cmd("enew")
  child.cmd("Logpose edit")
  H.contains(child.notifications()[#child.notifications()].msg, "works on a journal note")
end

return T

local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- no project here
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15) -- Thursday
    end,
    post_once = child.stop,
  },
})

--- The form's values, one per field.
local function values()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- What the form draws: per row its label and end-of-line text, and the lines below it.
local function drawn()
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local rows, below = {}, {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local row, d = m[2] + 1, m[4]
      rows[row] = rows[row] or { label = "", eol = "" }
      local text = table.concat(vim.tbl_map(function(c) return c[1] end, d.virt_text or {}))
      if d.virt_text_pos == "inline" then
        rows[row].label = vim.trim(text)
      elseif d.virt_text_pos == "eol" then
        rows[row].eol = vim.trim(text)
      end
      for _, vl in ipairs(d.virt_lines or {}) do
        local l = vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, vl)))
        if l ~= "" then
          table.insert(below, l)
        end
      end
    end
    return { rows = rows, below = below }
  end)()]])
end

--- Set the value on the row of field `key`.
local function set(key, value)
  local d = drawn()
  for row, r in pairs(d.rows) do
    if r.label == key then
      child.api.nvim_buf_set_lines(0, row - 1, row, false, { value })
      child.lua(
        "require('logpose.edit.form').render(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])"
      )
      return
    end
  end
  error("no field " .. key)
end

local function eol(key)
  for _, r in pairs(drawn().rows) do
    if r.label == key then
      return r.eol
    end
  end
end

local function save()
  child.cmd("stopinsert")
  child.type_keys("<C-s>")
end

T["meeting"] = MiniTest.new_set()

T["meeting"][":Logpose meeting opens the form; saving creates the note and opens it"] = function()
  child.cmd("Logpose meeting")
  eq(child.bo.filetype, "logpose-edit")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New meeting ")
  eq(values(), { "planning", "", "2026-10-15", "", "", "" })
  eq(child.fn.mode(), "i") -- typing the title right away
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
  H.contains(eol("title"), "empty: “Sprint planning”")
  set("type", "retro")
  H.contains(eol("title"), "empty: “Retro”")
  set("project", "acme")
  set("attendees", "Ana, Luis")
  set("tags", "q4, team")
  eq(drawn().below, {
    "saving will:",
    "• create meetings/acme/2026-10-15 - retro.md",
    "• link it from the daily note of Thu 15 Oct",
    "• tagged q4, team",
    "• then open it to write",
  })
  save()
  local path = root .. "/meetings/acme/2026-10-15 - retro.md"
  eq(child.api.nvim_buf_get_name(0), path) -- the form is gone, the note is open
  eq(child.lua_get("vim.tbl_count(require('logpose.edit.form').forms)"), 0)
  local text = H.read(path)
  H.contains(text, 'type: retro\ndate: 2026-10-15\nproject: acme\ntitle: "Retro"')
  H.contains(text, "attendees: [Ana, Luis]\ntags: [q4, team]\nseries: acme/retro")
  H.contains(H.read(root .. "/daily/daily-2026-10-15.md"), "- acme: [[meetings/acme/2026-10-15 - retro|Retro]]")
  H.contains(child.notifications()[#child.notifications()].msg, "created meetings/acme/2026-10-15 - retro.md")
end

T["meeting"]["a 1:1's title is the person; the type's own title can be replaced"] = function()
  child.cmd("Logpose meeting")
  set("type", "1on1")
  H.contains(eol("title"), "who it's with")
  save()
  H.contains(child.notifications()[#child.notifications()].msg, "needs who it's with")
  eq(child.bo.filetype, "logpose-edit") -- nothing created
  set("title", "Ana")
  eq(eol("title"), "→ 1:1 Ana")
  save()
  local text = H.read(root .. "/meetings/2026-10-15 - 1-1-ana.md")
  H.contains(text, 'title: "1:1 Ana"\nwith: "Ana"\nattendees: [Ana]')
  -- a fixed-title type takes another title
  child.cmd("Logpose meeting")
  set("type", "review")
  set("title", "Q4 review")
  save()
  H.contains(
    H.read(root .. "/meetings/2026-10-15 - q4-review.md"),
    'type: review\ndate: 2026-10-15\ntitle: "Q4 review"'
  )
end

T["meeting"]["the preview says what a series carries over; a date picks the day"] = function()
  H.write(
    root .. "/meetings/2026-10-08 - retro.md",
    '---\ntype: retro\ndate: 2026-10-08\ntitle: "Retro"\nseries: retro\n---\n## Action items\n\n- [ ] ship it\n- [ ] write ADR\n'
  )
  child.cmd("Logpose meeting 2026-10-22")
  eq(values()[3], "2026-10-22")
  set("type", "retro")
  eq(drawn().below, {
    "saving will:",
    "• create meetings/2026-10-22 - retro.md",
    "• link it from the daily note of Thu 22 Oct",
    "• carry over 2 open to-dos from Retro (Thu 8 Oct)",
    "• then open it to write",
  })
  save()
  H.contains(H.read(root .. "/meetings/2026-10-22 - retro.md"), "- [ ] ship it")
  H.contains(H.read(root .. "/meetings/2026-10-08 - retro.md"), "- [>] ship it")
end

T["meeting"]["one that exists is opened, not overwritten"] = function()
  H.write(root .. "/meetings/2026-10-15 - retro.md", "mine\n")
  child.cmd("Logpose meeting")
  set("type", "retro")
  eq(drawn().below[2], "• open the existing meetings/2026-10-15 - retro.md")
  save()
  eq(child.api.nvim_buf_get_name(0), root .. "/meetings/2026-10-15 - retro.md")
  eq(H.read(root .. "/meetings/2026-10-15 - retro.md"), "mine\n")
  H.contains(child.notifications()[#child.notifications()].msg, "already exists; opened it")
end

T["meeting"]["the title completes people for a 1:1 and past titles otherwise"] = function()
  H.write(
    root .. "/meetings/2026-10-01 - x.md",
    '---\ntype: adhoc\ndate: 2026-10-01\ntitle: "Vendor call"\nattendees: [Bob]\n---\n'
  )
  child.cmd("Logpose meeting")
  local function words(type)
    set("type", type)
    return child.lua_get(
      [[vim.tbl_map(function(it) return it.word end,
      require('logpose.edit.form').candidates(...))]],
      { root, "meeting", "title", "", { type = type } }
    )
  end
  eq(words("1on1"), { "Bob" })
  eq(words("adhoc"), { "Vendor call" })
end

T["meeting"]["an existing meeting's form has tags too"] = function()
  local path = root .. "/meetings/2026-10-14 - retro.md"
  H.write(path, '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\nattendees: [Ana]\n---\n')
  child.cmd("edit " .. path)
  child.cmd("Logpose edit")
  set("tags", "q4")
  child.cmd("write")
  H.contains(H.read(path), "tags: [q4]")
end

T["topic"] = MiniTest.new_set()

T["topic"][":Logpose note opens the form; saving creates the note with its project and tags"] = function()
  child.cmd("Logpose note")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New topic note ")
  eq(values(), { "", "", "" })
  save()
  H.contains(child.notifications()[#child.notifications()].msg, "give the note a title")
  set("title", "Queue design")
  set("project", "acme")
  set("tags", "adr, perf")
  eq(drawn().below, {
    "saving will:",
    "• create notes/queue-design.md, for acme",
    "• tagged adr, perf",
    "• then open it to write",
  })
  save()
  local path = root .. "/notes/queue-design.md"
  eq(child.api.nvim_buf_get_name(0), path)
  H.contains(H.read(path), 'title: "Queue design"\nproject: acme\ntags: [adr, perf]')
  -- with a title it's instant, as before
  child.cmd("Logpose note Other idea")
  eq(child.api.nvim_buf_get_name(0), root .. "/notes/other-idea.md")
end

T["the notes screen's a, n and m open the forms with its project"] = function()
  H.write(
    root .. "/meetings/acme/2026-10-14 - retro.md",
    '---\ntype: retro\ndate: 2026-10-14\ntitle: "Retro"\nproject: acme\n---\n'
  )
  child.lua("require('logpose.notes.browse').open(..., { project = 'acme' })", { root })
  child.type_keys("a") -- the cursor starts on the retro, in Meetings
  eq(child.api.nvim_win_get_config(0).title[1][1], " New meeting ")
  eq(values()[4], "acme")
  child.cmd("stopinsert")
  child.type_keys("q")
  child.type_keys("n")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New topic note ")
  eq(values()[2], "acme")
  child.cmd("stopinsert")
  child.type_keys("q")
  child.type_keys("m")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New meeting ")
end

return T

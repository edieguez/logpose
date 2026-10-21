local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root
local task

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
      H.write(root .. "/meetings/acme/2026-10-14 - retro.md", '---\ntitle: "Retro"\nproject: acme\n---\n')
      task = root .. "/tasks/queue-design.md"
      H.write(task, table.concat({
        "---",
        'title: "Queue design"',
        "status: in-progress",
        "project: acme",
        "tags: [adr]",
        "---",
        "## Context",
        "",
        "From: [[meetings/acme/2026-10-14 - retro|Retro]]",
        "",
        "We compared Kafka and SQS.",
        "",
        "### Decision",
        "",
        "SQS: cheaper, enough for our volume.",
        "",
        "## Log",
        "",
        "- 2026-10-14 09:00: created in Backlog",
      }, "\n") .. "\n")
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
  -- (saving rewrites the open task, whose markdown ftplugin then runs `sil! nunmap`: typing
  -- <C-s> would trip over the E31 it leaves in v:errmsg, so save directly)
  child.cmd("stopinsert")
  child.lua("require('logpose.edit.form').save(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])")
end

T[":Logpose promote in a task opens the form from the task; copy links both ways"] = function()
  child.cmd("edit " .. task)
  child.api.nvim_win_set_cursor(0, { 11, 0 })
  child.cmd("Logpose promote")
  eq(child.api.nvim_win_get_config(0).title[1][1], " Note from task ")
  eq(values(), { "Queue design", "acme", "adr", "copy" })
  eq(drawn().below, {
    "saving will:",
    "• create notes/queue-design.md, for acme",
    "• copy the task's write-up (4 lines; ## Log left out)",
    "• link the note and the task to each other",
    "• tagged adr",
    "• then open it to write",
  })
  save()
  local note = root .. "/notes/queue-design.md"
  eq(child.api.nvim_buf_get_name(0), note)
  local text = H.read(note)
  H.contains(text, 'title: "Queue design"\nproject: acme\ntags: [adr]')
  H.contains(text, "From: [[tasks/queue-design|Queue design]]\n\n## Context\n\nWe compared Kafka and SQS.")
  H.contains(text, "### Decision\n\nSQS: cheaper, enough for our volume.\n")
  eq(text:find("created in Backlog", 1, true), nil) -- not the log
  eq(text:find("From: [[meetings", 1, true), nil) -- the task's own origin stays with the task
  local t = H.read(task)
  H.contains(t, "We compared Kafka and SQS.") -- copied: still there
  H.contains(t, "## Notes\n\n- [[notes/queue-design|Queue design]]\n\n## Log")
  -- the board counts it as a note linked with the task
  child.cmd("Logpose board")
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "✎ 2")
end

T["move leaves only the link in the task; a selection takes just those lines"] = function()
  child.cmd("edit " .. task)
  child.cmd("13,15Logpose promote")
  set("title", "Queue decision")
  set("content", "move")
  eq(drawn().below[3], "• move the 3 selected lines")
  save()
  local text = H.read(root .. "/notes/queue-decision.md")
  H.contains(text, "From: [[tasks/queue-design|Queue design]]\n\n### Decision\n\nSQS: cheaper")
  eq(text:find("Kafka", 1, true), nil)
  local t = H.read(task)
  eq(t:find("SQS: cheaper", 1, true), nil) -- moved out
  H.contains(t, "We compared Kafka and SQS.") -- the rest stays
  H.contains(t, "## Notes\n\n- [[notes/queue-decision|Queue decision]]")
  -- a second note goes under the same ## Notes
  child.cmd("edit " .. task)
  child.cmd("Logpose promote")
  set("title", "Queue design")
  save()
  H.contains(H.read(task), "- [[notes/queue-decision|Queue decision]]\n- [[notes/queue-design|Queue design]]")
end

T["a note with that title gets the write-up added; content must be copy or move"] = function()
  H.write(root .. "/notes/queue-design.md", '---\ntitle: "Queue design"\n---\nEarlier thoughts.\n')
  child.cmd("edit " .. task)
  child.cmd("Logpose promote")
  set("content", "keep")
  H.contains(drawn().rows[4].eol, "copy or move")
  set("content", "copy")
  eq(drawn().below[2], "• add the task's write-up to the existing notes/queue-design.md")
  save()
  H.contains(H.read(root .. "/notes/queue-design.md"), "Earlier thoughts.\n\nFrom: [[tasks/queue-design|Queue design]]")
  H.contains(child.notifications()[#child.notifications()].msg, "added the task's write-up to notes/queue-design.md")
end

T["N on the board does it for the focused card; promote on a to-do still makes a task"] = function()
  child.cmd("Logpose board")
  child.type_keys("l", "l", "N") -- the task is In progress
  eq(child.api.nvim_win_get_config(0).title[1][1], " Note from task ")
  child.cmd("stopinsert")
  child.type_keys("q")
  -- a to-do in a note: a task, as before
  local daily = root .. "/daily/daily-2026-10-15.md"
  H.write(daily, "# d\n\n- [ ] write the ADR\n")
  child.cmd("edit " .. daily)
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Logpose promote")
  eq(vim.fn.filereadable(root .. "/tasks/write-the-adr.md"), 1)
end

return T

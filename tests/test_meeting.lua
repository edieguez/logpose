local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- outside any git repo: no project
      child.lua(("require('logpose').setup({ root = %q })"):format(root))
      H.freeze(child, 2026, 10, 14, 10, 30)
    end,
    post_once = child.stop,
  },
})

local function meeting(name)
  return root .. "/meetings/" .. name
end

local function daily(iso)
  return root .. "/daily/daily-" .. (iso or "2026-10-14") .. ".md"
end

--- Answer vim.ui.input / vim.ui.select in the child.
local function answer_input(value)
  child.lua(("vim.ui.input = function(_, cb) _G.input_asked = true; cb(%s) end"):format(vim.inspect(value)))
end
local function answer_select(pick)
  child.lua(([[vim.ui.select = function(items, opts, cb)
    _G.select_items = vim.tbl_map(function(i) return opts.format_item and opts.format_item(i) or i end, items)
    for _, item in ipairs(items) do
      local label = opts.format_item and opts.format_item(item) or item
      if label == %q then return cb(item) end
    end
    cb(nil)
  end]]):format(pick))
end

local function lines(path)
  return vim.split(H.read(path) or "", "\n", { plain = true })
end

T["planning: no prompt, frontmatter, cursor, daily link"] = function()
  child.cmd("Logpose meeting planning")
  local path = meeting("2026-10-14 - sprint-planning.md")
  eq(child.api.nvim_buf_get_name(0), path)
  eq(
    H.read(path),
    table.concat({
      "---",
      "type: planning",
      "date: 2026-10-14",
      'title: "Sprint planning"',
      "attendees: []",
      "series: planning",
      "created: 2026-10-14T10:30",
      "modified: 2026-10-14T10:30",
      "---",
      "## Sprint goal",
      "",
      "## Committed items",
      "",
      "## Risks",
      "",
      "## Action items",
      "",
    }, "\n")
  )
  eq(child.api.nvim_win_get_cursor(0), { 11, 0 })
  eq(child.lua_get("_G.input_asked"), vim.NIL)

  local d = H.read(daily())
  H.contains(d, "## Meetings\n\n- [[meetings/2026-10-14 - sprint-planning|Sprint planning]]\n\n## Notes")
end

T["adhoc: prompts, transliterates the filename, keeps the title"] = function()
  answer_input("Reunión con QA")
  child.cmd("Logpose meeting adhoc")
  local path = meeting("2026-10-14 - reunion-con-qa.md")
  eq(child.api.nvim_buf_get_name(0), path)
  H.contains(H.read(path), 'title: "Reunión con QA"')
  eq(H.read(path):find("\n# ", 1, true), nil) -- no H1 next to the frontmatter title (MD025)
  H.contains(H.read(path), "series: adhoc-reunion-con-qa")
end

T["filename and header format for ASCII titles"] = function()
  answer_input("Sprint Planning")
  child.cmd("Logpose meeting adhoc")
  local path = meeting("2026-10-14 - sprint-planning.md")
  H.contains(H.read(path), 'title: "Sprint Planning"\n')
end

T["1on1: title from the prompt, series per person"] = function()
  answer_input("Ana")
  child.cmd("Logpose meeting 1on1")
  local path = meeting("2026-10-14 - 1-1-ana.md")
  H.contains(H.read(path), 'title: "1:1 Ana"')
  H.contains(H.read(path), "series: 1on1-ana")
  H.contains(H.read(path), "## Follow-ups\n")
end

T["empty or cancelled input aborts"] = function()
  answer_input("   ")
  child.cmd("Logpose meeting adhoc")
  answer_input(nil)
  child.cmd("Logpose meeting adhoc")
  H.contains(child.notifications()[1].msg, "cancelled")
  eq(vim.fn.isdirectory(root .. "/meetings"), 0)
end

T["symbol-only titles fall back to the type name"] = function()
  answer_input("¿?")
  child.cmd("Logpose meeting adhoc")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-14 - adhoc.md"))
end

T["titles with quotes produce valid YAML"] = function()
  answer_input('Say "hi" \\ bye')
  child.cmd("Logpose meeting adhoc")
  H.contains(H.read(meeting("2026-10-14 - say-hi-bye.md")), [[title: "Say \"hi\" \\ bye"]])
end

T["without a type, opens the new-meeting form, starting on the first type"] = function()
  child.cmd("Logpose meeting")
  eq(child.bo.filetype, "logpose-edit")
  eq(child.api.nvim_buf_get_lines(0, 0, 1, false)[1], "planning") -- the first type
end

T["same type and title on the same day opens the existing note"] = function()
  child.cmd("Logpose meeting retro")
  child.cmd("enew!")
  H.write(meeting("2026-10-14 - retro.md"), "edited\n")
  child.cmd("Logpose meeting retro")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-14 - retro.md"))
  eq(H.read(meeting("2026-10-14 - retro.md")), "edited\n")
  local _, count = H.read(daily()):gsub("2026%-10%-14 %- retro", "")
  eq(count, 1)
end

T["{time} in the filename"] = MiniTest.new_set()

T["{time} in the filename"]["creates a second note when asked"] = function()
  child.lua(("require('logpose').setup({ root = %q, meeting_filename = '{date} {time} - {slug}' })"):format(root))
  child.cmd("Logpose meeting retro")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-14 1030 - retro.md"))
  H.freeze(child, 2026, 10, 14, 11, 0)
  answer_select("Create new")
  child.cmd("Logpose meeting retro")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-14 1100 - retro.md"))
  local d = H.read(daily())
  H.contains(d, "1030 - retro")
  H.contains(d, "1100 - retro")
end

T["{time} in the filename"]["can open the existing note instead"] = function()
  child.lua(("require('logpose').setup({ root = %q, meeting_filename = '{date} {time} - {slug}' })"):format(root))
  child.cmd("Logpose meeting retro")
  child.cmd("enew")
  H.freeze(child, 2026, 10, 14, 11, 0)
  answer_select("Open existing")
  child.cmd("Logpose meeting retro")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-14 1030 - retro.md"))
  eq(vim.fn.filereadable(meeting("2026-10-14 1100 - retro.md")), 0)
end

T["accepts a date for backfilling"] = function()
  child.cmd("Logpose meeting retro 2026-10-12")
  eq(child.api.nvim_buf_get_name(0), meeting("2026-10-12 - retro.md"))
  H.contains(H.read(meeting("2026-10-12 - retro.md")), "date: 2026-10-12")
  H.contains(H.read(daily("2026-10-12")), "[[meetings/2026-10-12 - retro|Retro]]")
end

T["uses a template from the journal"] = function()
  H.write(root .. "/templates/retro.md", "# {title} ({weekday})\n{cursor}\n")
  child.cmd("Logpose meeting retro")
  H.contains(H.read(meeting("2026-10-14 - retro.md")), "---\n# Retro (Wednesday)\n")
end

T["markdown link style"] = function()
  child.lua(("require('logpose').setup({ root = %q, link_style = 'markdown' })"):format(root))
  child.cmd("Logpose meeting review")
  H.contains(H.read(daily()), "- [Sprint review](<../meetings/2026-10-14 - sprint-review.md>)")
end

T["adds the link to an unsaved daily buffer without losing edits"] = function()
  child.cmd("Logpose daily")
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# typed but not saved" })
  local before = H.read(daily())
  child.o.hidden = true
  child.cmd("Logpose meeting retro")
  eq(H.read(daily()), before)
  local buf = child.fn.bufnr(daily())
  local text = table.concat(child.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.contains(text, "# typed but not saved")
  H.contains(text, "[[meetings/2026-10-14 - retro|Retro]]")
  H.contains(child.notifications()[1].msg, "unsaved")
end

T["custom and disabled types"] = function()
  child.lua(([[require('logpose').setup({ root = %q, meeting_types = {
    refinement = false,
    standup = { label = "Standup", title = "Standup", order = 1 },
  } })]]):format(root))
  eq(
    child.fn.getcompletion("Logpose meeting ", "cmdline"),
    { "standup", "planning", "review", "retro", "1on1", "adhoc" }
  )
  child.cmd("Logpose meeting standup")
  H.contains(H.read(meeting("2026-10-14 - standup.md")), "## Decisions") -- falls back to meeting.md
  child.cmd("Logpose meeting refinement")
  H.contains(child.notifications()[1].msg, 'unknown meeting type "refinement"')
end

T["rejects bad arguments"] = function()
  child.cmd("Logpose meeting retro 2026-13-01")
  H.contains(child.notifications()[1].msg, "invalid date")
end

T["insert_under_heading"] = MiniTest.new_set()

local function insert(input, item, marker)
  return child.lua_get(
    ("require('logpose.notes.meeting').insert_under_heading(%s, 'Meetings', %q, %q)"):format(
      vim.inspect(input),
      item,
      marker or item
    )
  )
end

T["insert_under_heading"]["appends to an empty section before the next heading"] = function()
  eq(insert({ "# d", "", "## Meetings", "", "## Notes" }, "- a"), { "# d", "", "## Meetings", "- a", "", "## Notes" })
end

T["insert_under_heading"]["appends after existing items"] = function()
  eq(insert({ "## Meetings", "- a", "", "## Notes" }, "- b"), { "## Meetings", "- a", "- b", "", "## Notes" })
end

T["insert_under_heading"]["creates the heading when missing"] = function()
  eq(insert({ "# d", "text", "" }, "- a"), { "# d", "text", "", "## Meetings", "- a" })
end

T["insert_under_heading"]["is idempotent"] = function()
  eq(insert({ "## Meetings", "- [[x|X]]" }, "- [[x|Other]]", "x"), vim.NIL)
end

T["insert_under_heading"]["works at the end of the file"] = function()
  eq(insert({ "## Meetings", "- a" }, "- b"), { "## Meetings", "- a", "- b" })
end

return T

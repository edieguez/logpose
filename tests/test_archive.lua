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
      child.lua(("require('logpose').setup({ root = %q })"):format(root))
      H.freeze(child, 2026, 10, 14) -- current week starts 2026-10-12
    end,
    post_once = child.stop,
  },
})

local function p(rel)
  return root .. "/" .. rel
end

local function lines(...)
  return table.concat({ ... }, "\n") .. "\n"
end

local INBOX = lines(
  "# INBOX",
  "",
  "## 2026-10-05",
  "- [ ] a",
  "- [ ] b",
  "",
  "## 2026-10-07",
  "- [ ] c",
  "",
  "## 2026-09-29",
  "- [ ] old",
  "",
  "## 2026-10-12",
  "- [ ] current",
  "",
  "## 2026-10-14",
  "- [ ] today"
)

T["moves past weeks into one file per week and keeps the current week"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("Logpose archive!")
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-12", "- [ ] current", "", "## 2026-10-14", "- [ ] today"))
  eq(
    H.read(p("journal-entries/week-2026-10-05.md")),
    lines("# Journal: week of 2026-10-05", "", "## 2026-10-05", "- [ ] a", "- [ ] b", "", "## 2026-10-07", "- [ ] c")
  )
  eq(
    H.read(p("journal-entries/week-2026-09-28.md")),
    lines("# Journal: week of 2026-09-28", "", "## 2026-09-29", "- [ ] old")
  )
  H.contains(child.notifications()[1].msg, "archived 3 sections into 2 files")
end

T["archives DONE.md into done-entries"] = function()
  H.write(p("DONE.md"), lines("# DONE", "", "## 2026-10-08", "- [x] shipped", "", "## 2026-10-13", "- [x] now"))
  child.cmd("Logpose archive!")
  eq(H.read(p("DONE.md")), lines("# DONE", "", "## 2026-10-13", "- [x] now"))
  eq(
    H.read(p("done-entries/done-week-2026-10-05.md")),
    lines("# Done: week of 2026-10-05", "", "## 2026-10-08", "- [x] shipped")
  )
end

T["merges into an existing week file"] = function()
  H.write(p("INBOX.md"), INBOX)
  H.write(
    p("journal-entries/week-2026-10-05.md"),
    lines("# My week", "", "## 2026-10-07", "- [x] earlier", "", "## 2026-10-09", "- [ ] friday")
  )
  child.cmd("Logpose archive!")
  eq(
    H.read(p("journal-entries/week-2026-10-05.md")),
    lines(
      "# My week",
      "",
      "## 2026-10-05",
      "- [ ] a",
      "- [ ] b",
      "",
      "## 2026-10-07",
      "- [x] earlier",
      "- [ ] c",
      "",
      "## 2026-10-09",
      "- [ ] friday"
    )
  )
end

T["follows newest-first files"] = function()
  H.write(
    p("INBOX.md"),
    lines("# INBOX", "", "## 2026-10-13", "- [ ] now", "", "## 2026-10-07", "- [ ] c", "", "## 2026-10-05", "- [ ] a")
  )
  child.cmd("Logpose archive!")
  eq(
    H.read(p("journal-entries/week-2026-10-05.md")),
    lines("# Journal: week of 2026-10-05", "", "## 2026-10-07", "- [ ] c", "", "## 2026-10-05", "- [ ] a")
  )
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-13", "- [ ] now"))
end

T["section_order can be forced"] = function()
  child.lua(("require('logpose').setup({ root = %q, section_order = 'newest_first' })"):format(root))
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-05", "- [ ] a", "", "## 2026-10-07", "- [ ] c"))
  child.cmd("Logpose archive!")
  eq(
    H.read(p("journal-entries/week-2026-10-05.md")),
    lines("# Journal: week of 2026-10-05", "", "## 2026-10-07", "- [ ] c", "", "## 2026-10-05", "- [ ] a")
  )
end

T["crosses the year boundary"] = function()
  H.freeze(child, 2026, 1, 7)
  H.write(
    p("INBOX.md"),
    lines(
      "# INBOX",
      "",
      "## 2025-12-30",
      "- [ ] dec",
      "",
      "## 2026-01-02",
      "- [ ] jan",
      "",
      "## 2026-01-05",
      "- [ ] now"
    )
  )
  child.cmd("Logpose archive!")
  eq(
    H.read(p("journal-entries/week-2025-12-29.md")),
    lines("# Journal: week of 2025-12-29", "", "## 2025-12-30", "- [ ] dec", "", "## 2026-01-02", "- [ ] jan")
  )
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-01-05", "- [ ] now"))
end

T["keeps non-date sections and the preamble"] = function()
  H.write(
    p("INBOX.md"),
    lines(
      "# INBOX",
      "Intro text.",
      "",
      "## Someday",
      "- idea",
      "",
      "## 2026-10-05",
      "- [ ] a",
      "",
      "## Waiting",
      "- reply"
    )
  )
  child.cmd("Logpose archive!")
  eq(H.read(p("INBOX.md")), lines("# INBOX", "Intro text.", "", "## Someday", "- idea", "", "## Waiting", "- reply"))
end

T["leaves no trailing blank lines when the last section moves"] = function()
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-13", "- [ ] now", "", "## 2026-10-05", "- [ ] a", "", ""))
  child.cmd("Logpose archive!")
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-13", "- [ ] now"))
end

T["archiving everything leaves just the title"] = function()
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-05", "- [ ] a"))
  child.cmd("Logpose archive!")
  eq(H.read(p("INBOX.md")), lines("# INBOX"))
end

T["nothing to archive touches nothing"] = function()
  local current = lines("# INBOX", "", "## 2026-10-12", "- [ ] current")
  H.write(p("INBOX.md"), current)
  child.cmd("Logpose archive")
  H.contains(child.notifications()[1].msg, "nothing to archive")
  eq(H.read(p("INBOX.md")), current)
  eq(vim.fn.isdirectory(p("journal-entries")), 0)
end

T["missing INBOX/DONE are fine"] = function()
  child.cmd("Logpose archive!")
  H.contains(child.notifications()[1].msg, "nothing to archive")
end

T["a second run has nothing to do"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("Logpose archive!")
  child.cmd("Logpose archive!")
  H.contains(child.notifications()[2].msg, "nothing to archive")
end

T["re-running after an interrupted archive doesn't duplicate"] = function()
  H.write(p("INBOX.md"), lines("# INBOX", "", "## 2026-10-05", "- [ ] a", "", "## 2026-10-13", "- [ ] now"))
  -- as if the archive file was written but INBOX.md wasn't
  local week = lines("# Journal: week of 2026-10-05", "", "## 2026-10-05", "- [ ] a")
  H.write(p("journal-entries/week-2026-10-05.md"), week)
  child.cmd("Logpose archive!")
  eq(H.read(p("journal-entries/week-2026-10-05.md")), week)
  eq(H.read(p("INBOX.md")), lines("# INBOX", "", "## 2026-10-13", "- [ ] now"))
end

T["refuses when INBOX.md has unsaved changes, writing nothing"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# INBOX (edited)" })
  child.cmd("Logpose archive!")
  H.contains(child.notifications()[1].msg, "INBOX.md has unsaved changes")
  eq(H.read(p("INBOX.md")), INBOX)
  eq(vim.fn.isdirectory(p("journal-entries")), 0)
end

T["reloads a clean INBOX.md buffer"] = function()
  H.write(p("INBOX.md"), INBOX)
  child.cmd("edit " .. p("INBOX.md"))
  child.cmd("Logpose archive!")
  eq(child.api.nvim_buf_get_lines(0, 0, 3, false), { "# INBOX", "", "## 2026-10-12" })
end

local function stub_select(choice)
  child.lua(([[vim.ui.select = function(items, opts, cb)
    _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    _G.preview_name = vim.api.nvim_buf_get_name(0)
    _G.items = items
    cb(%s)
  end]]):format(vim.inspect(choice)))
end

T["preview"] = MiniTest.new_set()

T["preview"]["lists the moves and asks before writing"] = function()
  H.write(p("INBOX.md"), INBOX)
  H.write(p("journal-entries/week-2026-09-28.md"), lines("# W", "", "## 2026-09-29", "- [ ] old"))
  stub_select("Archive")
  child.cmd("Logpose archive")
  eq(child.lua_get("_G.items"), { "Archive", "Cancel" })
  local preview = table.concat(child.lua_get("_G.preview"), "\n")
  H.contains(preview, "Archive sections from before the week of 2026-10-12")
  H.contains(preview, "INBOX.md\n  → journal-entries/week-2026-09-28.md (merge): 2026-09-29 (already there)")
  H.contains(preview, "  → journal-entries/week-2026-10-05.md (new): 2026-10-05, 2026-10-07")
  H.contains(child.lua_get("_G.preview_name"), "logpose://archive-preview")
  eq(#child.api.nvim_list_wins(), 1) -- preview closed
  H.contains(H.read(p("INBOX.md")), "## 2026-10-12")
  eq(vim.fn.filereadable(p("journal-entries/week-2026-10-05.md")), 1)
end

T["preview"]["cancel writes nothing"] = function()
  H.write(p("INBOX.md"), INBOX)
  stub_select("Cancel")
  child.cmd("Logpose archive")
  eq(H.read(p("INBOX.md")), INBOX)
  eq(vim.fn.isdirectory(p("journal-entries")), 0)
  eq(#child.api.nvim_list_wins(), 1)
  H.contains(child.notifications()[1].msg, "cancelled")
end

T["honours custom dirs, affixes and titles"] = function()
  child.lua(([[require('logpose').setup({
    root = %q,
    dirs = { inbox = "journal/INBOX.md", journal_entries = "journal/weeks" },
    affixes = { week = "w-" },
    archive = { journal_title = "# Semana {period}" },
  })]]):format(root))
  H.write(p("journal/INBOX.md"), INBOX)
  child.cmd("Logpose archive!")
  eq(H.read(p("journal/weeks/w-2026-09-28.md")), lines("# Semana 2026-09-28", "", "## 2026-09-29", "- [ ] old"))
end

T["completes as a subcommand"] = function()
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose ", "cmdline"), "archive"), true)
end

return T

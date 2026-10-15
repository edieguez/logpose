local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.lua(("require('logpose').setup({ root = %q })"):format(root))
    end,
    post_once = child.stop,
  },
})

local function build()
  return child.lua_get(("require('logpose.index').build(%q)"):format(root))
end

local function tags(line)
  return child.lua_get(("require('logpose.index').tags_in(%q)"):format(line))
end

T["tags_in"] = MiniTest.new_set()

T["tags_in"]["finds inline tags, lowercased"] = function()
  eq(tags("fix #Perf and #acme-api, (#ux) [#a/b]"), { "perf", "acme-api", "ux", "a/b" })
end

T["tags_in"]["ignores headings, URL fragments, numbers and mid-word #"] = function()
  eq(tags("# Heading"), {})
  eq(tags("## 2026-10-14"), {})
  eq(tags("see http://x.com/#frag and C# and issue #123"), {})
  eq(tags("trailing #tag- and #tag/"), { "tag", "tag" })
end

T["frontmatter"] = function()
  local fm = child.lua_get(
    [[{ require('logpose.index').frontmatter({ "---", "type: retro", 'title: "Say \"hi\""', "tags: [a, 'b', \"c\"]", "attendees: []", "---", "# x" }) }]]
  )
  eq(fm[1], { type = "retro", title = 'Say "hi"', tags = { "a", "b", "c" }, attendees = {} })
  eq(fm[2], 7)
  eq(child.lua_get([[{ require('logpose.index').frontmatter({ "---", "type: x" }) }]]), { {}, 1 })
end

T["notes get title, date, type, project and tags"] = function()
  H.write(root .. "/meetings/acme/2026-10-14 - retro.md", table.concat({
    "---",
    "type: retro",
    "date: 2026-10-14",
    "project: Acme",
    'title: "Retro"',
    "tags: [team, Perf]",
    "---",
    "# 2026-10-14 - Retro meeting notes",
    "- [ ] follow up #perf",
    "- [x] done one",
    "Note with #idea",
  }, "\n") .. "\n")
  local items = build()
  eq(#items, 4)
  local note, open, done, line = items[1], items[2], items[3], items[4]
  eq(
    { note.kind, note.text, note.date, note.note_type, note.type, note.project, note.lnum },
    { "note", "Retro", "2026-10-14", "meeting", "retro", "acme", 1 }
  )
  eq(note.tags, { "team", "perf", "idea" })
  eq(note.fm_tags, { "team", "perf" })
  eq(
    { open.kind, open.text, open.checked, open.lnum, open.project, open.title },
    { "task", "follow up #perf", false, 9, "acme", "Retro" }
  )
  eq(open.tags, { "perf" })
  eq({ done.checked, done.text }, { true, "done one" })
  eq({ line.kind, line.text, line.tags }, { "line", "Note with #idea", { "idea" } })
end

T["falls back to the heading, then the filename; dates from filenames"] = function()
  H.write(root .. "/daily/daily-2026-10-13.md", "# Tuesday notes\n- [ ] x\n")
  H.write(root .. "/misc/plain.md", "just text\n")
  local items = build()
  local by_file = {}
  for _, it in ipairs(items) do
    if it.kind == "note" then
      by_file[vim.fs.basename(it.file)] = it
    end
  end
  eq({ by_file["daily-2026-10-13.md"].text, by_file["daily-2026-10-13.md"].date }, { "Tuesday notes", "2026-10-13" })
  eq(by_file["daily-2026-10-13.md"].note_type, "daily")
  eq({ by_file["plain.md"].text, by_file["plain.md"].date, by_file["plain.md"].note_type }, { "plain", nil, "other" })
end

T["task dates come from the enclosing day section"] = function()
  H.write(root .. "/INBOX.md", "# INBOX\n\n## 2026-10-12\n- [ ] a\n\n## Someday\n- [ ] b\n\n## 2026-10-13\n- [ ] c\n")
  local items = build()
  eq(items[1].note_type, "inbox")
  eq({ items[2].date, items[3].date, items[4].date }, { "2026-10-12", nil, "2026-10-13" })
end

T["classifies INBOX, DONE and archives"] = function()
  H.write(root .. "/DONE.md", "# DONE\n")
  H.write(root .. "/journal-entries/week-2026-10-05.md", "# W\n")
  H.write(root .. "/done-entries/done-sprint-41.md", "# D\n")
  local types = {}
  for _, it in ipairs(build()) do
    types[vim.fs.basename(it.file)] = it.note_type
  end
  eq(types, { ["DONE.md"] = "done", ["week-2026-10-05.md"] = "archive", ["done-sprint-41.md"] = "archive" })
end

T["skips templates and dot-directories"] = function()
  H.write(root .. "/templates/retro.md", "# {title}\n- [ ] {cursor}\n")
  H.write(root .. "/.git/notes.md", "# git\n")
  H.write(root .. "/.obsidian/x.md", "# x\n")
  H.write(root .. "/real.md", "# real\n")
  local files = vim.tbl_map(function(it)
    return vim.fs.basename(it.file)
  end, build())
  eq(files, { "real.md" })
end

T["sections"] = function()
  H.write(root .. "/meetings/2026-10-14 - retro.md", table.concat({
    "---",
    "date: 2026-10-14",
    "---",
    "# Retro",
    "## Went well",
    "- pairing",
    "## Decisions",
    "- Use Postgres for the queue",
    "Keep sprints at two weeks",
    "",
    "- [ ] write ADR",
    "### Details",
    "- sub point",
    "## Action items",
    "- [ ] ship it #acme",
  }, "\n") .. "\n")
  H.write(root .. "/INBOX.md", "# INBOX\n## Blockers\n- waiting on infra\n## 2026-10-13\n- [ ] dated task\n")
  local items = build()
  local got = {}
  for _, it in ipairs(items) do
    if it.kind ~= "note" then
      table.insert(got, { it.kind, it.text, it.section or false, it.section_title or false })
    end
  end
  eq(got, {
    { "line", "waiting on infra", "blockers", "Blockers" },
    { "task", "dated task", false, false },
    { "line", "Use Postgres for the queue", "decisions", "Decisions" },
    { "line", "Keep sprints at two weeks", "decisions", "Decisions" },
    { "task", "write ADR", "decisions", "Decisions" },
    { "line", "sub point", "decisions", "Decisions" },
    { "task", "ship it #acme", "action items", "Action items" },
  })
end

T["retrieval sections are configurable"] = function()
  child.lua(("require('logpose').setup({ root = %q, retrieval = { sections = { 'went well' } } })"):format(root))
  H.write(root .. "/m.md", "# M\n## Went well\n- pairing\n## Decisions\n- nope\n")
  local texts = {}
  for _, it in ipairs(build()) do
    if it.kind == "line" then
      table.insert(texts, it.text)
    end
  end
  eq(texts, { "pairing" })
end

T["tag_counts and projects"] = function()
  H.write(root .. "/INBOX.md", "# INBOX\n- [ ] a #perf\n- [ ] b #perf #ux\n")
  H.write(root .. "/m.md", "---\nproject: thesis\ntags: [perf]\n---\n# M\n")
  eq(child.lua_get(("require('logpose.index').tag_counts(require('logpose.index').build(%q))"):format(root)), {
    { tag = "perf", count = 3 },
    { tag = "ux", count = 1 },
  })
  eq(
    child.lua_get(("require('logpose.index').projects(require('logpose.index').build(%q))"):format(root)),
    { "thesis" }
  )
end

return T

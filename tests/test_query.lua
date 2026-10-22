local H = dofile("tests/helpers.lua")
local query = require("logpose.query")
local eq = H.eq

local T = MiniTest.new_set()

local function m(item, args, today)
  return query.match(item, query.parse(args, today or "2026-10-14"))
end

T["parse rejects bad dates"] = function()
  MiniTest.expect.error(function()
    query.parse({ "since:someday" })
  end, "since: needs a date")
  MiniTest.expect.error(function()
    query.parse({ "date>=someday" })
  end, "date: needs a date")
end

local dated = function(d)
  return { kind = "note", text = "x", tags = {}, date = d }
end

T["relative dates"] = function()
  eq(m(dated("2026-10-07"), { "since:-7d", "until:yesterday" }), true)
  eq(m(dated("2026-10-06"), { "since:-7d" }), false)
  eq(m(dated("2026-10-14"), { "until:yesterday" }), false)
  eq(m(dated("2026-10-28"), { "until:+2w" }), true)
  eq(m(dated("2026-10-29"), { "until:+2w" }), false)
end

T["week: and sprint: expand to a date range"] = function()
  eq(m(dated("2026-10-12"), { "week:current" }), true)
  eq(m(dated("2026-10-18"), { "week:current" }), true)
  eq(m(dated("2026-10-11"), { "week:current" }), false)
  eq(m(dated("2026-10-05"), { "week:-1" }), true)
  MiniTest.expect.error(function()
    query.parse({ "sprint:current" }, "2026-10-14")
  end, "needs `period.sprint.anchor`")
  MiniTest.expect.error(function()
    query.parse({ "week:soon" }, "2026-10-14")
  end, "week: expects current")
end

T["section filter"] = function()
  local q = query.parse({ "section:open-questions" })
  eq(query.match({ kind = "line", text = "x", tags = {}, section = "open questions" }, q), true)
  eq(query.match({ kind = "line", text = "x", tags = {}, section = "decisions" }, q), false)
  eq(query.match({ kind = "line", text = "x", tags = {} }, q), false)
end

local task = {
  kind = "task",
  text = "Fix flaky test",
  title = "INBOX",
  checked = false,
  date = "2026-10-13",
  tags = { "perf", "acme" },
}
local note = {
  kind = "note",
  text = "Retro",
  title = "Retro",
  date = "2026-10-14",
  type = "retro",
  project = "thesis",
  tags = { "team" },
}

T["match"] = MiniTest.new_set()

T["match"]["project matches the project or a tag"] = function()
  eq(m(note, { "project:thesis" }), true)
  eq(m(task, { "project:acme" }), true)
  eq(m(task, { "project:thesis" }), false)
end

T["match"]["tags must all be present"] = function()
  eq(m(task, { "#perf" }), true)
  eq(m(task, { "#perf", "#acme" }), true)
  eq(m(task, { "#perf", "#ux" }), false)
end

T["match"]["type, state and dates"] = function()
  eq(m(note, { "type:retro" }), true)
  eq(m(task, { "type:retro" }), false)
  eq(m(task, { "open" }), true)
  eq(m(task, { "done" }), false)
  eq(m(note, { "open" }), false)
  eq(m(task, { "since:2026-10-13", "until:2026-10-13" }), true)
  eq(m(task, { "since:2026-10-14" }), false)
  eq(m({ kind = "note", text = "x", tags = {} }, { "since:2026-01-01" }), false)
end

T["match"]["words search text and note title"] = function()
  eq(m(task, { "flaky" }), true)
  eq(m(task, { "inbox", "fix" }), true)
  eq(m(task, { "flaky", "nope" }), false)
end

T["lenient parse skips half-typed and invalid filters"] = function()
  local q, skipped =
    query.parse({ "project:", "#", "@", "since:2026-1", "sprint:", "#perf", "open", "flaky" }, "2026-10-14", true)
  eq(#skipped, 5)
  eq(query.match(task, q), true)
  eq(query.split("  #perf   open "), { "#perf", "open" })
  eq(query.split(""), {})
  eq(query.split('attendees:"Ana López" (a or b)'), { "attendees:Ana López", "(", "a", "or", "b", ")" })
  -- an open parenthesis while typing
  eq(query.match(task, query.parse({ "(#perf", "or" }, nil, true)), true)
  MiniTest.expect.error(function()
    query.parse({ "(#perf" })
  end, "a %( without its %)")
end

local meeting = {
  kind = "note",
  file_type = "meeting",
  type = "retro",
  text = "Retro",
  title = "Retro",
  date = "2026-10-14",
  project = "acme",
  tags = { "team" },
  people = { "ana", "bob-smith" },
  fields = {
    type = "retro",
    date = "2026-10-14",
    attendees = { "Ana", "Bob Smith" },
    room = "Lisboa",
    score = "7",
  },
}
local daily = { kind = "note", file_type = "daily", text = "d", tags = {}, date = "2026-10-13", fields = {} }

T["or, not and parentheses"] = function()
  eq(m(meeting, { "type:planning", "or", "type:retro" }), true)
  eq(m(meeting, { "type:planning", "OR", "type:review" }), false)
  eq(m(meeting, { "not", "type:retro" }), false)
  eq(m(meeting, { "-type:retro" }), false)
  eq(m(meeting, { "-#draft" }), true)
  eq(m(meeting, { "(type:planning", "or", "type:retro)", "project:acme" }), true)
  eq(m(meeting, { "(type:planning", "or", "type:retro)", "project:thesis" }), false)
  eq(m(meeting, { "type:planning", "or", "type:retro", "project:thesis" }), false) -- and binds tighter
  eq(m(meeting, { "#team", "and", "@ana" }), true)
  eq(m(meeting, { "-7d" }), false) -- a word, not a negation
  eq(m(meeting, { "-(type:planning", "or", "type:retro)" }), false)
  eq(m(daily, { "-(type:daily", "or", "type:meeting)" }), false)
  eq(m(daily, { "-(type:meeting)" }), true)
end

T["type: is the meeting type or the kind of note"] = function()
  eq(m(meeting, { "type:meeting" }), true)
  eq(m(daily, { "type:daily" }), true)
  eq(m(meeting, { "type:daily" }), false)
  eq(m(daily, { "-type:daily" }), false)
end

T["any frontmatter field"] = function()
  eq(m(meeting, { "room:lisboa" }), true)
  eq(m(meeting, { "room:lis" }), true) -- contains, accents and case ignored
  eq(m(meeting, { "room:madrid" }), false)
  eq(m(meeting, { "room:*" }), true)
  eq(m(meeting, { "has:room" }), true)
  eq(m(meeting, { "no:room" }), false)
  eq(m(meeting, { "no:due" }), true)
  eq(m(meeting, { "score>=7" }), true)
  eq(m(meeting, { "score>7" }), false)
  eq(m(meeting, { "score<10" }), true) -- numbers compare as numbers
end

T["attendees and with match people, partly typed"] = function()
  eq(m(meeting, { "attendees:ana" }), true)
  eq(m(meeting, { "attendees:bob" }), true)
  eq(m(meeting, { 'attendees:"Bob Smith"' }), true)
  eq(m(meeting, { "attendees:carla" }), false)
  eq(m(meeting, { "with:ana" }), false)
end

T["dates: a day, a month, comparisons and ranges"] = function()
  eq(m(meeting, { "date:2026-10-14" }), true)
  eq(m(meeting, { "date:2026-10" }), true)
  eq(m(meeting, { "date:2026-09" }), false)
  eq(m(meeting, { "date:2026" }), true)
  eq(m(meeting, { "date:today" }), true)
  eq(m(meeting, { "date>=-7d" }), true)
  eq(m(meeting, { "date<today" }), false)
  eq(m(meeting, { "date<=2026-10" }), true) -- the whole month
  eq(m(meeting, { "date>2026-09" }), true)
  eq(m(meeting, { "date>2026-10" }), false)
  eq(m(meeting, { "date:2026-10-01..2026-10-15" }), true)
  eq(m(meeting, { "date:2026-10-15..2026-10-31" }), false)
  eq(m(meeting, { "date:..2026-10" }), true)
end

return T

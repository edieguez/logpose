local H = dofile("tests/helpers.lua")
local query = require("logpose.query")
local eq = H.eq

local T = MiniTest.new_set()

T["parse"] = function()
  eq(
    query.parse({
      "project:Acme",
      "#Perf",
      "tag:#ux",
      "type:retro",
      "open",
      "since:2026-10-01",
      "until:2026-10-14",
      "Flaky",
      "Test",
    }),
    {
      project = "acme",
      tags = { "perf", "ux" },
      type = "retro",
      state = "open",
      since = "2026-10-01",
      ["until"] = "2026-10-14",
      words = { "flaky", "test" },
    }
  )
  eq(query.parse({ "p:x" }).project, "x")
  eq(query.parse({}), { tags = {}, words = {} })
end

T["parse rejects bad dates"] = function()
  MiniTest.expect.error(function()
    query.parse({ "since:yesterday" })
  end, "since: needs a YYYY%-MM%-DD date")
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

local function m(item, args)
  return query.match(item, query.parse(args))
end

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

return T

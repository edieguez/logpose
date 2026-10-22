local H = dofile("tests/helpers.lua")
local fm = require("logpose.frontmatter")
local eq = H.eq

local T = MiniTest.new_set()

T["values are quoted only when YAML needs it"] = function()
  eq(fm.render("title", "Retro"), '"Retro"') -- titles always
  eq(fm.render("status", "in-progress"), "in-progress")
  eq(fm.render("blocked", "waiting on: ana"), '"waiting on: ana"')
  eq(fm.render("blocked", "#later"), '"#later"')
  eq(fm.render("tags", { "ci", "a,b", "perf" }), '[ci, "a,b", perf]')
  eq(fm.render("tags", {}), "[]")
  eq(fm.render("order", 2), "2")
  eq(fm.render("archived", true), "true")
  eq(fm.line("due", ""), "due:")
  eq(fm.line("due", nil), "due:")
  eq(fm.quote('say "hi"'), '"say \\"hi\\""')
end

T["set rewrites keys in place, removes with false, adds by rank"] = function()
  local lines = { "---", "title: x", "status: todo", "due:", "---", "body" }
  eq(fm.set(lines, { status = "done", due = false }), { "---", "title: x", "status: done", "---", "body" })
  -- new keys: by rank when given, else at the end in name order
  eq(
    fm.set(lines, { project = "acme" }, { order = { "title", "status", "project", "due" } }),
    { "---", "title: x", "status: todo", "project: acme", "due:", "---", "body" }
  )
  eq(
    fm.set(lines, { zeta = "1", alpha = "2" }),
    { "---", "title: x", "status: todo", "due:", "alpha: 2", "zeta: 1", "---", "body" }
  )
  -- an empty value for a key that isn't there adds nothing
  eq(fm.set(lines, { blocked = "" }), lines)
  -- the input isn't changed
  eq(lines[3], "status: todo")
end

T["a note without frontmatter gets one"] = function()
  eq(fm.set({ "# hi" }, { title = "Hi", tags = { "x" } }), { "---", "tags: [x]", 'title: "Hi"', "---", "# hi" })
  eq(fm.set({ "# hi" }, { due = "" }), { "# hi" })
end

T["read lists keys in order with their values"] = function()
  local entries, close = fm.read({ "---", 'title: "A: b"', "tags: [x, y]", "---", "text" })
  eq(close, 4)
  eq(entries, { { key = "title", value = "A: b" }, { key = "tags", value = { "x", "y" } } })
end

T["lists with commas and quotes read back as written"] = function()
  local items = { "Lopez, Ana", 'Ana "Ani"', [[back\slash]], "plain" }
  local lines = { "---", fm.line("aliases", items), "---" }
  eq(fm.read(lines), { { key = "aliases", value = items } })
  eq(fm.read({ "---", "tags: [a, 'b, c', , d ]", "---" }), { { key = "tags", value = { "a", "b, c", "d" } } })
end

T["block lists: read as lists, replaced whole"] = function()
  local lines = { "---", "tags:", "  - perf", '  - "ci"', "due:", "---", "- body" }
  eq(fm.read(lines), { { key = "tags", value = { "perf", "ci" } }, { key = "due", value = "" } })
  eq(fm.set(lines, { tags = { "perf" } }), { "---", "tags: [perf]", "due:", "---", "- body" })
  eq(fm.set(lines, { tags = false }), { "---", "due:", "---", "- body" })
end

return T

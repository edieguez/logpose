local H = dofile("tests/helpers.lua")
local template = require("logpose.template")
local eq = H.eq

local T = MiniTest.new_set()

T["substitute"] = MiniTest.new_set()

T["substitute"]["replaces known variables and keeps unknown ones"] = function()
  eq(template.substitute("{date} {title} {nope}", { date = "2026-10-14", title = "Retro" }), "2026-10-14 Retro {nope}")
end

T["substitute"]["is safe with % and braces in values"] = function()
  eq(template.substitute("# {title}", { title = "100% {date} done %1" }), "# 100% {date} done %1")
end

T["render"] = MiniTest.new_set()

T["render"]["removes {cursor} and reports its position"] = function()
  local r = template.render("# {title}\n\n## Notes\n- {cursor}\n\n## End\n", { title = "Hi" })
  eq(r.text, "# Hi\n\n## Notes\n- \n\n## End\n")
  eq(r.cursor, { 4, 2 })
end

T["render"]["handles {cursor} at the very start and repeated markers"] = function()
  local r = template.render("{cursor}a{cursor}b", {})
  eq(r.text, "ab")
  eq(r.cursor, { 1, 0 })
end

T["render"]["defaults the cursor to the last non-empty line"] = function()
  local r = template.render("# {date}\n\nbody\n\n", { date = "2026-10-14" })
  eq(r.cursor, { 3, 0 })
end

T["vars"] = function()
  local vars = template.vars("2026-10-14", { title = "Retro" })
  eq(vars.date, "2026-10-14")
  eq(vars.weekday, "Wednesday")
  eq(vars.iso_week, "2026-W42")
  eq(vars.sprint, "")
  eq(vars.title, "Retro")
  H.neq(vars.time:match("^%d%d:%d%d$"), nil)
end

T["load"] = MiniTest.new_set()

T["load"]["prefers the journal's templates dir"] = function()
  local root = H.journal()
  H.write(root .. "/templates/retro.md", "custom {title}\n")
  local content, path = template.load("retro", root)
  eq(content, "custom {title}\n")
  eq(path, root .. "/templates/retro.md")
end

T["load"]["falls back to the shipped templates"] = function()
  local root = H.journal()
  for _, name in ipairs({ "daily", "meeting", "planning", "refinement", "review", "retro", "1on1" }) do
    local content = template.load(name, root)
    H.neq(content:find("{cursor}", 1, true), nil)
  end
end

T["load"]["errors for a missing template"] = function()
  MiniTest.expect.error(function()
    template.load("nope", H.journal())
  end, 'template "nope" not found')
end

return T

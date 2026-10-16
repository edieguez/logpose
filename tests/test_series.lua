local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra or "{}"))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- no project
      setup()
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function answer(value)
  child.lua(("vim.ui.input = function(_, cb) cb(%q) end"):format(value))
end

local function m(name)
  return root .. "/meetings/" .. name
end

--- First 1:1 with Ana on 2026-10-07, with follow-ups.
local function first_one_on_one()
  answer("Ana")
  child.cmd("Logpose meeting 1on1 2026-10-07")
  local path = m("2026-10-07 - 1-1-ana.md")
  local content = H.read(path)
    :gsub("## Follow%-ups\n$", "## Follow-ups\n\n- [ ] send feedback\n- [x] done item\n- [ ] book room\n")
  H.write(path, content)
  child.cmd("enew!")
  return path
end

T["a new 1:1 links the previous one and carries open follow-ups"] = function()
  local old = first_one_on_one()
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  local new = H.read(m("2026-10-14 - 1-1-ana.md"))
  H.contains(
    new,
    table.concat({
      "series: 1on1-ana",
      "---",
      "Previous: [[meetings/2026-10-07 - 1-1-ana|1:1 Ana 2026-10-07]]",
      "",
      "## Carried over",
      "",
      "- [ ] send feedback (from [[meetings/2026-10-07 - 1-1-ana|2026-10-07]])",
      "- [ ] book room (from [[meetings/2026-10-07 - 1-1-ana|2026-10-07]])",
      "",
      "## Topics",
      "",
    }, "\n")
  )
  -- cursor still lands under ## Topics
  eq(child.api.nvim_get_current_line(), "")
  eq(child.fn.getline(child.fn.line(".") - 1), "## Topics")
  -- carried items are marked as migrated in the old note
  H.contains(H.read(old), "- [>] send feedback\n- [x] done item\n- [>] book room\n")
end

T["carried items aren't listed twice by :Logpose actions"] = function()
  first_one_on_one()
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  child.cmd("Logpose actions")
  local texts = vim.tbl_map(function(e)
    return e.text
  end, child.fn.getqflist())
  eq(#texts, 2)
  H.contains(texts[1], "send feedback (from")
end

T["a different person starts a new series"] = function()
  first_one_on_one()
  answer("Bob")
  child.cmd("Logpose meeting 1on1")
  local new = H.read(m("2026-10-14 - 1-1-bob.md"))
  eq(new:find("Previous:", 1, true), nil)
  eq(new:find("Carried over", 1, true), nil)
end

T["series are project-scoped"] = function()
  child.cmd("Logpose project acme")
  child.cmd("Logpose meeting retro 2026-10-07")
  child.cmd("Logpose project thesis")
  child.cmd("Logpose meeting retro")
  eq(H.read(m("thesis/2026-10-14 - retro.md")):find("Previous:", 1, true), nil)
  child.cmd("Logpose project acme")
  child.cmd("Logpose meeting retro")
  H.contains(H.read(m("acme/2026-10-14 - retro.md")), "Previous: [[meetings/acme/2026-10-07 - retro|Retro 2026-10-07]]")
end

T["an item carried twice keeps one, current origin"] = function()
  first_one_on_one()
  answer("Ana")
  child.cmd("Logpose meeting 1on1 2026-10-10")
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  local new = H.read(m("2026-10-14 - 1-1-ana.md"))
  H.contains(new, "- [ ] send feedback (from [[meetings/2026-10-10 - 1-1-ana|2026-10-10]])\n")
  H.contains(new, "Previous: [[meetings/2026-10-10 - 1-1-ana|1:1 Ana 2026-10-10]]")
  H.contains(H.read(m("2026-10-10 - 1-1-ana.md")), "- [>] send feedback (from")
end

T["the most recent earlier note is the previous one"] = function()
  first_one_on_one()
  answer("Ana")
  child.cmd("Logpose meeting 1on1 2026-10-21") -- a later note must not count
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  H.contains(H.read(m("2026-10-14 - 1-1-ana.md")), "Previous: [[meetings/2026-10-07 - 1-1-ana|")
end

T["carry_over = false only links"] = function()
  local old = first_one_on_one()
  setup("{ series = { carry_over = false } }")
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  local new = H.read(m("2026-10-14 - 1-1-ana.md"))
  H.contains(new, "Previous: ")
  eq(new:find("Carried over", 1, true), nil)
  H.contains(H.read(old), "- [ ] send feedback\n")
end

T["mark_carried = false leaves the old note alone"] = function()
  local old = first_one_on_one()
  setup("{ series = { mark_carried = false } }")
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  H.contains(H.read(m("2026-10-14 - 1-1-ana.md")), "## Carried over")
  H.contains(H.read(old), "- [ ] send feedback\n")
end

T["marks an unsaved previous note in its buffer"] = function()
  local old = first_one_on_one()
  child.o.hidden = true
  child.cmd("edit " .. vim.fn.fnameescape(old))
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "typing" })
  local before = H.read(old)
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  eq(H.read(old), before)
  local buf = child.fn.bufnr(old)
  local text = table.concat(child.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.contains(text, "- [>] send feedback")
  H.contains(text, "typing")
end

T["markdown links"] = function()
  first_one_on_one()
  setup("{ link_style = 'markdown' }")
  answer("Ana")
  child.cmd("Logpose meeting 1on1")
  H.contains(H.read(m("2026-10-14 - 1-1-ana.md")), "- [ ] send feedback (from [2026-10-07](<2026-10-07 - 1-1-ana.md>))")
end

return T

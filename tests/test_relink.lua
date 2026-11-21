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
      child.cmd("cd " .. H.tmpdir())
      setup()
      H.freeze(child, 2026, 10, 15)
    end,
    post_once = child.stop,
  },
})

local function p(rel)
  return root .. "/" .. rel
end

local function retro(iso, body)
  H.write(
    p("meetings/" .. iso .. " - retro.md"),
    ('---\ntype: retro\ndate: %s\ntitle: "Retro"\nseries: retro\n---\n%s'):format(iso, body or "## Went well\n")
  )
end

T["adds the links that notes made before them lack, and moves a series' Previous: line"] = function()
  H.write(p("daily/daily-2026-10-12.md"), "---\nmodified: 2026-10-12T18:00\n---\n# Mon\n")
  H.write(p("daily/daily-2026-10-14.md"), "# Wed\n")
  retro("2026-10-01")
  retro(
    "2026-10-15",
    "Previous: [[meetings/2026-10-01 - retro|Retro 2026-10-01]]\n\n## Carried over\n\n- [ ] ship it (from [[meetings/2026-10-01 - retro|2026-10-01]])\n"
  )
  child.cmd("Logpose relink!")
  -- bookkeeping, not an edit: modified: stays
  eq(
    H.read(p("daily/daily-2026-10-12.md")),
    '---\nnext: "[[daily/daily-2026-10-14|Wed 2026-10-14]]"\nmodified: 2026-10-12T18:00\n---\n# Mon\n'
  )
  eq(H.read(p("daily/daily-2026-10-14.md")), '---\nprevious: "[[daily/daily-2026-10-12|Mon 2026-10-12]]"\n---\n# Wed\n')
  H.contains(
    H.read(p("meetings/2026-10-01 - retro.md")),
    'series: retro\nnext: "[[meetings/2026-10-15 - retro|Retro 2026-10-15]]"\n---\n## Went well\n'
  )
  eq(
    H.read(p("meetings/2026-10-15 - retro.md")),
    table.concat({
      "---",
      "type: retro",
      "date: 2026-10-15",
      'title: "Retro"',
      "series: retro",
      'previous: "[[meetings/2026-10-01 - retro|Retro 2026-10-01]]"',
      "---",
      "## Carried over",
      "",
      "- [ ] ship it (from [[meetings/2026-10-01 - retro|2026-10-01]])",
      "",
    }, "\n")
  )
  H.contains(child.notifications()[1].msg, "updated 4 files")
  child.cmd("Logpose relink!")
  H.contains(child.notifications()[2].msg, "nothing to change")
end

T["fixes the links a deleted note leaves behind"] = function()
  for _, iso in ipairs({ "2026-10-12", "2026-10-13", "2026-10-14" }) do
    child.cmd("Logpose daily " .. iso)
  end
  child.cmd("%bwipeout!")
  vim.fn.delete(p("daily/daily-2026-10-13.md"))
  child.cmd("Logpose relink!")
  H.contains(H.read(p("daily/daily-2026-10-12.md")), 'next: "[[daily/daily-2026-10-14|Wed 2026-10-14]]"')
  H.contains(H.read(p("daily/daily-2026-10-14.md")), 'previous: "[[daily/daily-2026-10-12|Mon 2026-10-12]]"')
  -- the last one gone: the note before it has no next
  vim.fn.delete(p("daily/daily-2026-10-14.md"))
  child.cmd("Logpose relink!")
  eq(H.read(p("daily/daily-2026-10-12.md")):find("next:", 1, true), nil)
end

T["shows what it changes and asks first"] = function()
  H.write(p("daily/daily-2026-10-12.md"), "# Mon\n")
  H.write(p("daily/daily-2026-10-14.md"), "# Wed\n")
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    _G.prompt = opts.prompt
    cb("Cancel")
  end]])
  child.cmd("Logpose relink")
  local preview = table.concat(child.lua_get("_G.preview"), "\n")
  H.contains(preview, "Relink daily notes and meeting series")
  H.contains(preview, "daily/daily-2026-10-12.md (1 change)\n  daily/daily-2026-10-14.md (1 change)")
  eq(child.lua_get("_G.prompt"), "Relink daily notes and meeting series?")
  eq(H.read(p("daily/daily-2026-10-12.md")), "# Mon\n") -- cancelled
end

T["refuses while a note has unsaved changes"] = function()
  H.write(p("daily/daily-2026-10-12.md"), "# Mon\n")
  H.write(p("daily/daily-2026-10-14.md"), "# Wed\n")
  child.cmd("edit " .. p("daily/daily-2026-10-12.md"))
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "typing" })
  child.cmd("Logpose relink!")
  H.contains(child.notifications()[1].msg, "unsaved changes")
  eq(H.read(p("daily/daily-2026-10-14.md")), "# Wed\n")
end

T["leaves alone what links = false turns off"] = function()
  setup("{ daily = { links = false }, series = { links = false } }")
  H.write(p("daily/daily-2026-10-12.md"), "# Mon\n")
  H.write(p("daily/daily-2026-10-14.md"), "# Wed\n")
  retro("2026-10-01")
  retro("2026-10-15", "Previous: [[meetings/2026-10-01 - retro|Retro 2026-10-01]]\n")
  child.cmd("Logpose relink!")
  H.contains(child.notifications()[1].msg, "nothing to change")
end

T["completes as a subcommand"] = function()
  eq(vim.tbl_contains(child.fn.getcompletion("Logpose re", "cmdline"), "relink"), true)
end

return T

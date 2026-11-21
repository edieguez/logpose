local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

-- Window options editors often turn on for files (LazyVim does most of them): a screen leaves
-- them out.
local KEYS = {
  "number",
  "relativenumber",
  "signcolumn",
  "foldcolumn",
  "statuscolumn",
  "colorcolumn",
  "cursorcolumn",
  "list",
  "spell",
}
local OFF = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  statuscolumn = "",
  colorcolumn = "",
  cursorcolumn = false,
  list = false,
  spell = false,
}

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 14)
      H.write(
        root .. "/meetings/2026-10-13 - retro.md",
        '---\ntype: retro\ndate: 2026-10-13\ntitle: "Retro"\nattendees: [Ana]\n---\n## Notes\n\n- [ ] ship it @ana\n'
      )
      H.write(root .. "/tasks/fix-it.md", '---\ntitle: "Fix it"\nstatus: in-progress\n---\n## Context\n')
      H.write(root .. "/notes/ideas.md", '---\ntitle: "Ideas"\n---\nSome ideas.\n')
      child.lua([[
        vim.o.number, vim.o.relativenumber, vim.o.signcolumn = true, true, "yes"
        vim.o.colorcolumn, vim.o.cursorcolumn, vim.o.list, vim.o.spell = "120", true, true, true
        vim.o.foldcolumn, vim.o.statuscolumn = "1", "%l "
        vim.o.wrap, vim.o.cursorline = true, false
      ]])
    end,
    post_once = child.stop,
  },
})

--- The current window's values of `keys` (default `KEYS`).
local function options(keys)
  return child.lua_get(
    ("(function() local o = {} for _, k in ipairs(%s) do o[k] = vim.wo[k] end return o end)()"):format(
      vim.inspect(keys or KEYS)
    )
  )
end

T["screens leave out line numbers, signs, columns, list characters and spell checking"] = function()
  local got, want = {}, {}
  for _, name in ipairs({ "board", "today", "meetings", "notes", "people", "projects" }) do
    child.cmd("Logpose " .. name)
    got[name], want[name] = options(), OFF
  end
  eq(got, want)
end

T["so do the help window, the filter bar, the edit form and previews"] = function()
  local got = {}
  child.cmd("Logpose meetings")
  child.type_keys("?")
  got.help = options()
  child.type_keys("q")
  child.type_keys("/")
  got.filter = options()
  child.type_keys("<Esc>")
  child.cmd("edit " .. root .. "/tasks/fix-it.md")
  child.cmd("Logpose edit")
  got.form = options()
  child.cmd("stopinsert")
  child.type_keys("q")
  child.cmd("Logpose stats")
  got.preview = options()
  local bar = vim.deepcopy(OFF)
  bar.statuscolumn = got.filter.statuscolumn -- the bar's own: its prompt
  H.contains(bar.statuscolumn, "Filter meetings")
  eq(got, { help = OFF, filter = bar, form = OFF, preview = OFF })
end

T["a note opened from a screen, or gone back to, keeps your options"] = function()
  local keys = { "number", "relativenumber", "spell", "list", "colorcolumn", "wrap", "cursorline", "winbar" }
  local mine = {
    number = true,
    relativenumber = true,
    spell = true,
    list = true,
    colorcolumn = "120",
    wrap = true,
    cursorline = false,
    winbar = "",
  }
  child.cmd("edit " .. root .. "/notes/ideas.md")
  child.cmd("Logpose meetings")
  for i, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find("Retro", 1, true) then
      child.api.nvim_win_set_cursor(0, { i, 0 })
    end
  end
  child.type_keys("<CR>") -- opens the retro in the list's window
  eq(child.api.nvim_buf_get_name(0), root .. "/meetings/2026-10-13 - retro.md")
  eq(options(keys), mine)
  child.cmd("Logpose people")
  child.type_keys("q")
  eq(child.api.nvim_buf_get_name(0), root .. "/meetings/2026-10-13 - retro.md")
  eq(options(keys), mine)
end

T["any window that shows a screen gets its options"] = function()
  child.cmd("Logpose meetings")
  child.cmd("new")
  eq(options({ "number", "spell" }), { number = true, spell = true }) -- a window of yours
  child.cmd("buffer logpose://meetings")
  eq(options(), OFF)
end

return T

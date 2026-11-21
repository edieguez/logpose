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
      H.freeze(child, 2026, 10, 14) -- Wednesday
    end,
    post_once = child.stop,
  },
})

local function daily_path(iso)
  return root .. "/daily/daily-" .. iso .. ".md"
end

local function bufname()
  return child.api.nvim_buf_get_name(0)
end

T["creates today's note and puts the cursor under ## Notes"] = function()
  child.cmd("Logpose daily")
  eq(bufname(), daily_path("2026-10-14"))
  eq(
    H.read(daily_path("2026-10-14")),
    "---\ncreated: 2026-10-14T10:30\nmodified: 2026-10-14T10:30\n---\n# 2026-10-14 daily notes\n\n## Notes\n"
  )
  eq(child.api.nvim_win_get_cursor(0), { 9, 0 })
  eq(child.bo.modified, false)
end

T["saving the new note untouched leaves no trailing blank lines"] = function()
  child.cmd("Logpose daily")
  child.type_keys("i", "a thought", "<Esc>")
  child.cmd("write")
  H.contains(H.read(daily_path("2026-10-14")), "## Notes\n\na thought\n")
  child.cmd("bwipe!")
  vim.fn.delete(daily_path("2026-10-14"))
  child.cmd("Logpose daily")
  child.cmd("write")
  eq(H.read(daily_path("2026-10-14")):sub(-9), "## Notes\n")
end

T["header format"] = function()
  child.cmd("Logpose daily")
  eq(vim.split(H.read(daily_path("2026-10-14")), "\n")[5], "# 2026-10-14 daily notes")
end

T["opens an existing note without overwriting it"] = function()
  H.write(daily_path("2026-10-14"), "# mine\n")
  child.cmd("Logpose daily today")
  eq(bufname(), daily_path("2026-10-14"))
  eq(H.read(daily_path("2026-10-14")), "# mine\n")
end

T["works from a buffer in another repo"] = function()
  local other = H.tmpdir()
  child.cmd("cd " .. other)
  child.cmd("edit " .. other .. "/main.go")
  child.cmd("Logpose daily")
  eq(bufname(), daily_path("2026-10-14"))
end

T["prev on a Monday opens Friday's note"] = function()
  H.write(daily_path("2026-10-08"), "# Thu\n")
  H.write(daily_path("2026-10-09"), "# Fri\n")
  H.freeze(child, 2026, 10, 12)
  child.cmd("Logpose daily prev")
  eq(bufname(), daily_path("2026-10-09"))
end

T["prev/next step between the notes there are, from the one in the current buffer"] = function()
  for _, iso in ipairs({ "2026-10-05", "2026-10-08", "2026-10-12" }) do
    H.write(daily_path(iso), "# " .. iso .. "\n")
  end
  child.cmd("edit " .. daily_path("2026-10-08"))
  child.cmd("Logpose daily next")
  eq(bufname(), daily_path("2026-10-12"))
  child.cmd("Logpose daily prev")
  child.cmd("Logpose daily prev")
  eq(bufname(), daily_path("2026-10-05"))
  -- the days in between (a weekend, a day off) never get a note
  eq(vim.fn.readdir(root .. "/daily"), { "daily-2026-10-05.md", "daily-2026-10-08.md", "daily-2026-10-12.md" })
end

T["next reaches today's note, making it if needed; past either end it says so"] = function()
  H.write(daily_path("2026-10-12"), "# Mon\n")
  child.cmd("edit " .. daily_path("2026-10-12"))
  child.cmd("Logpose daily next")
  eq(bufname(), daily_path("2026-10-14"))
  H.contains(H.read(daily_path("2026-10-14")), "# 2026-10-14 daily notes")
  child.cmd("Logpose daily next")
  H.contains(child.notifications()[1].msg, "no daily note after Wed 14 Oct")
  child.cmd("edit " .. daily_path("2026-10-12"))
  child.cmd("Logpose daily prev")
  H.contains(child.notifications()[2].msg, "no daily note before Mon 12 Oct")
  eq(bufname(), daily_path("2026-10-12"))
end

T["from a buffer that isn't a daily note, prev and next go from today"] = function()
  H.write(daily_path("2026-10-12"), "# Mon\n")
  H.write(daily_path("2026-10-20"), "# a week on\n")
  child.cmd("Logpose daily prev")
  eq(bufname(), daily_path("2026-10-12"))
  child.cmd("enew")
  child.cmd("Logpose daily next")
  eq(bufname(), daily_path("2026-10-20"))
end

T["rejects invalid dates"] = function()
  child.cmd("Logpose daily 2026-02-30")
  H.contains(child.notifications()[1].msg, 'invalid date "2026-02-30"')
  eq(H.read(daily_path("2026-02-30")), nil)
end

T["uses a template from the journal"] = function()
  H.write(root .. "/templates/daily.md", "# {weekday} {date}\n{cursor}\n")
  child.cmd("Logpose daily")
  -- no trailing blank line in the file (MD012); the buffer gets a line to write on, below
  eq(
    H.read(daily_path("2026-10-14")),
    "---\ncreated: 2026-10-14T10:30\nmodified: 2026-10-14T10:30\n---\n# Wednesday 2026-10-14\n"
  )
  eq(child.api.nvim_win_get_cursor(0), { 7, 0 })
end

T["{sprint} names the current sprint when an anchor is set"] = function()
  H.write(root .. "/templates/daily.md", "# {date} {sprint}\n")
  child.cmd("Logpose daily")
  eq(
    H.read(daily_path("2026-10-14")),
    "---\ncreated: 2026-10-14T10:30\nmodified: 2026-10-14T10:30\n---\n# 2026-10-14\n"
  ) -- no trailing space (MD009)
  child.lua(
    ("require('logpose').setup({ root = %q, period = { sprint = { anchor = '2026-10-01', first_number = 42 } } })"):format(
      root
    )
  )
  child.cmd("Logpose daily 2026-10-15")
  H.contains(H.read(daily_path("2026-10-15")), "---\n# 2026-10-15 sprint-43\n")
end

T["honours configured dirs and affixes"] = function()
  child.lua(
    ("require('logpose').setup({ root = %q, dirs = { daily = 'notes' }, affixes = { daily = 'd-' } })"):format(root)
  )
  child.cmd("Logpose daily")
  eq(bufname(), root .. "/notes/d-2026-10-14.md")
end

T["completes arguments"] = function()
  eq(child.fn.getcompletion("Logpose daily ", "cmdline"), { "today", "prev", "next" })
end

T["without a journal, offers to create one and continues"] = function()
  child.lua("require('logpose').setup({})")
  child.cmd("cd " .. H.tmpdir())
  local new = H.tmpdir() .. "/my journal"
  child.lua(("vim.ui.input = function(opts, cb) _G.prompt = opts.prompt; cb(%q) end"):format(new))
  child.cmd("Logpose daily")
  H.contains(child.lua_get("_G.prompt"), "No journal found")
  eq(bufname(), new .. "/daily/daily-2026-10-14.md")
end

T["without a journal, cancelling explains how to set one up"] = function()
  child.lua("require('logpose').setup({})")
  child.cmd("cd " .. H.tmpdir())
  child.lua("vim.ui.input = function(_, cb) cb(nil) end")
  child.cmd("Logpose daily")
  H.contains(child.notifications()[1].msg, "run :Logpose init")
end

return T

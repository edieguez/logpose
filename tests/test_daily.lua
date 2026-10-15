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

T["creates today's note and puts the cursor under ## Today"] = function()
  child.cmd("Logpose daily")
  eq(bufname(), daily_path("2026-10-14"))
  eq(
    H.read(daily_path("2026-10-14")),
    "# 2026-10-14 daily notes\n\n## Yesterday\n\n## Today\n\n\n## Blockers\n\n## Meetings\n\n## Notes\n"
  )
  eq(child.api.nvim_win_get_cursor(0), { 6, 0 })
end

T["header matches the Python script's format"] = function()
  child.cmd("Logpose daily")
  eq(vim.split(H.read(daily_path("2026-10-14")), "\n")[1], "# 2026-10-14 daily notes")
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

T["prev on a Monday opens Friday"] = function()
  H.freeze(child, 2026, 10, 12)
  child.cmd("Logpose daily prev")
  eq(bufname(), daily_path("2026-10-09"))
end

T["prev/next step from the daily note in the current buffer"] = function()
  child.cmd("Logpose daily 2026-10-09")
  child.cmd("Logpose daily next")
  eq(bufname(), daily_path("2026-10-12"))
  child.cmd("Logpose daily prev")
  child.cmd("Logpose daily prev")
  eq(bufname(), daily_path("2026-10-08"))
end

T["respects custom workdays"] = function()
  child.lua(("require('logpose').setup({ root = %q, workdays = { 1, 3, 5 } })"):format(root))
  child.cmd("Logpose daily next") -- Wed -> Fri
  eq(bufname(), daily_path("2026-10-16"))
end

T["rejects invalid dates"] = function()
  child.cmd("Logpose daily 2026-02-30")
  H.contains(child.notifications()[1].msg, 'invalid date "2026-02-30"')
  eq(H.read(daily_path("2026-02-30")), nil)
end

T["uses a template from the journal"] = function()
  H.write(root .. "/templates/daily.md", "# {weekday} {date}\n{cursor}\n")
  child.cmd("Logpose daily")
  eq(H.read(daily_path("2026-10-14")), "# Wednesday 2026-10-14\n\n")
  eq(child.api.nvim_win_get_cursor(0), { 2, 0 })
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

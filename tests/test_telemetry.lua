local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(
    ("require('logpose').setup(vim.tbl_extend('force', { root = %q, picker = 'select' }, %s))"):format(
      root,
      extra or "{}"
    )
  )
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      H.freeze(child, 2026, 10, 14)
      child.lua("vim.ui.select = function(_, _, cb) cb(nil) end")
    end,
    post_once = child.stop,
  },
})

local function usage_path()
  return child.lua_get("require('logpose.telemetry').path()")
end

local function usage()
  child.lua("require('logpose.telemetry').flush()")
  return vim.json.decode(H.read(usage_path()))
end

T["off by default: nothing is recorded"] = function()
  setup()
  child.cmd("Logpose daily")
  child.lua("require('logpose.telemetry').flush()")
  eq(H.read(usage_path()), nil)
  child.cmd("Logpose stats")
  H.contains(child.notifications()[1].msg, "usage stats are off")
end

T["counts commands per day, with scope keywords, without arguments"] = function()
  setup("{ telemetry = { enabled = true } }")
  H.write(root .. "/INBOX.md", "# INBOX\n- [ ] secret task #private\n")
  child.cmd("Logpose daily")
  child.cmd("Logpose daily")
  child.cmd("Logpose daily prev")
  child.cmd("Logpose find tasks #private")
  child.cmd("Logpose find tasks open")
  child.cmd("Logpose daily 2026-02-30")
  child.cmd("Logpose nope")
  local data = usage()
  eq(data.days["2026-10-14"], {
    daily = { ok = 2, err = 1 },
    ["daily prev"] = { ok = 1, err = 0 },
    ["find tasks"] = { ok = 2, err = 0 },
  })
  local raw = H.read(usage_path())
  for _, secret in ipairs({ "private", "secret", "2026-02-30", root }) do
    eq(raw:find(secret, 1, true), nil)
  end
end

T["writes at most once per throttle window"] = function()
  setup("{ telemetry = { enabled = true } }")
  child.cmd("Logpose daily")
  eq(usage().days["2026-10-14"].daily.ok, 1)
  child.cmd("Logpose daily")
  -- not flushed yet: the file still has the first count
  eq(vim.json.decode(H.read(usage_path())).days["2026-10-14"].daily.ok, 1)
  eq(usage().days["2026-10-14"].daily.ok, 2) -- explicit flush (also runs on VimLeavePre)
end

T["old days are pruned"] = function()
  H.write(usage_path(), vim.json.encode({ version = 1, days = { ["2025-01-01"] = { daily = { ok = 9, err = 0 } } } }))
  setup("{ telemetry = { enabled = true, retention_days = 30 } }")
  child.cmd("Logpose daily")
  local data = usage()
  eq(data.days["2025-01-01"], nil)
  eq(data.days["2026-10-14"].daily.ok, 1)
end

T[":Logpose stats shows counts, trend and unused commands; ! resets"] = function()
  setup("{ telemetry = { enabled = true } }")
  H.write(
    usage_path(),
    vim.json.encode({
      version = 1,
      days = {
        ["2026-10-14"] = { daily = { ok = 3, err = 0 }, ["find tasks"] = { ok = 1, err = 1 } },
        ["2026-10-03"] = { daily = { ok = 2, err = 0 } },
      },
    })
  )
  child.cmd("Logpose stats")
  local text = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  H.contains(text, "# logpose usage, last 30 days")
  H.contains(text, "| daily | 5 | 3 | 2 | 0 |\n| find tasks | 2 | 2 | 0 | 1 |")
  H.contains(text, "## Not used in this period\nactions, archive,")
  eq(text:find("stats,", 1, true), nil)
  child.cmd("close")
  child.cmd("Logpose stats!")
  eq(H.read(usage_path()), nil)
end

return T

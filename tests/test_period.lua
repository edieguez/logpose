local H = dofile("tests/helpers.lua")
local period = require("logpose.period")
local eq = H.eq

local T = MiniTest.new_set()

-- Thursday-to-Wednesday two-week sprints; sprint 42 starts on 2026-10-01 (a Thursday).
local SPRINT = {
  kind = "sprint",
  week_start = 1,
  sprint = { anchor = "2026-10-01", length_days = 14, first_number = 42, name = "sprint-{n}" },
}

local function sprint(iso, opts)
  local p = period.of(iso, opts or SPRINT)
  return { p.key, p.start, p.finish, p.number }
end

T["sprints"] = MiniTest.new_set()

T["sprints"]["the anchor sprint runs Thursday to Wednesday"] = function()
  eq(sprint("2026-10-01"), { "sprint-42", "2026-10-01", "2026-10-14", 42 })
  eq(sprint("2026-10-14"), { "sprint-42", "2026-10-01", "2026-10-14", 42 })
  eq(period.of("2026-10-14", SPRINT).label, "sprint-42 (2026-10-01 – 2026-10-14)")
end

T["sprints"]["counts forward and backward from the anchor"] = function()
  eq(sprint("2026-10-15"), { "sprint-43", "2026-10-15", "2026-10-28", 43 })
  eq(sprint("2026-09-30"), { "sprint-41", "2026-09-17", "2026-09-30", 41 })
  eq(sprint("2027-01-01"), { "sprint-48", "2026-12-24", "2027-01-06", 48 })
  eq(sprint("2026-01-01"), { "sprint-22", "2025-12-25", "2026-01-07", 22 })
end

T["sprints"]["are stable across DST changes"] = function()
  local opts = vim.deepcopy(SPRINT)
  opts.sprint.anchor = "2026-03-05" -- US DST starts 2026-03-08
  opts.sprint.first_number = 1
  eq(sprint("2026-03-18", opts), { "sprint-1", "2026-03-05", "2026-03-18", 1 })
  eq(sprint("2026-03-19", opts), { "sprint-2", "2026-03-19", "2026-04-01", 2 })
  eq(sprint("2026-11-12", opts)[2], "2026-11-12") -- 18 sprints later, after DST ends
end

T["sprints"]["every day maps to the sprint that contains it"] = function()
  local d = "2026-01-01"
  while d < "2027-01-01" do
    local p = period.of(d, SPRINT)
    assert(p.start <= d and d <= p.finish, d)
    eq(require("logpose.util.date").weekday(p.start), 4) -- Thursday
    d = require("logpose.util.date").add_days(d, 1)
  end
end

T["sprints"]["use the name format"] = function()
  local opts = vim.deepcopy(SPRINT)
  opts.sprint.name = "S{n}"
  eq(sprint("2026-10-15", opts)[1], "S43")
end

T["weeks"] = MiniTest.new_set()

T["weeks"]["start on Monday by default"] = function()
  local p = period.of("2026-10-14", { kind = "week", week_start = 1, sprint = {} })
  eq({ p.key, p.start, p.finish, p.label }, { "2026-10-12", "2026-10-12", "2026-10-18", "week of 2026-10-12" })
end

T["weeks"]["can start on Thursday"] = function()
  local opts = { kind = "week", week_start = 4, sprint = {} }
  eq(period.of("2026-10-14", opts).start, "2026-10-08")
  eq(period.of("2026-10-15", opts).start, "2026-10-15")
  eq(period.of("2026-10-15", opts).finish, "2026-10-21")
end

return T

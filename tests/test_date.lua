local H = dofile("tests/helpers.lua")
local date = require("logpose.util.date")
local eq = H.eq

local T = MiniTest.new_set()

T["parse_iso"] = MiniTest.new_set()

T["parse_iso"]["parses valid dates"] = function()
  eq({ date.parse_iso("2026-10-14") }, { 2026, 10, 14 })
  eq({ date.parse_iso("2028-02-29") }, { 2028, 2, 29 })
end

T["parse_iso"]["rejects malformed and impossible dates"] = function()
  for _, s in ipairs({ "2026-1-5", "2026-02-30", "2027-02-29", "2026-13-01", "2026-00-10", "x", "", "2026-10-14 " }) do
    eq(date.parse_iso(s), nil)
  end
  eq(date.parse_iso(nil), nil)
end

T["today / now_hhmm use the clock source"] = function()
  local orig = date._now
  date._now = function()
    return os.time({ year = 2026, month = 10, day = 14, hour = 9, min = 5 })
  end
  eq(date.today(), "2026-10-14")
  eq(date.now_hhmm(), "0905")
  date._now = orig
end

T["add_days"] = MiniTest.new_set()

T["add_days"]["crosses month, year and leap day"] = function()
  eq(date.add_days("2026-10-31", 1), "2026-11-01")
  eq(date.add_days("2026-12-31", 1), "2027-01-01")
  eq(date.add_days("2028-02-28", 1), "2028-02-29")
  eq(date.add_days("2026-03-01", -1), "2026-02-28")
  eq(date.add_days("2026-10-14", 0), "2026-10-14")
  eq(date.add_days("2026-10-14", -365), "2025-10-14")
end

T["add_days"]["raises on invalid dates"] = function()
  MiniTest.expect.error(function()
    date.add_days("2026-02-30", 1)
  end, "invalid date")
end

T["weekday"] = function()
  eq(date.weekday("2026-10-12"), 1) -- Monday
  eq(date.weekday("2026-10-14"), 3)
  eq(date.weekday("2026-10-18"), 7) -- Sunday
  eq(date.weekday_name("2026-10-14"), "Wednesday")
end

T["monday_of"] = MiniTest.new_set()

T["monday_of"]["maps every day of a week to its Monday"] = function()
  for i = 0, 6 do
    eq(date.monday_of(date.add_days("2026-10-12", i)), "2026-10-12")
  end
end

T["monday_of"]["maps Sunday to the previous Monday"] = function()
  eq(date.monday_of("2026-10-18"), "2026-10-12")
end

T["monday_of"]["handles the year boundary"] = function()
  eq(date.monday_of("2026-01-01"), "2025-12-29")
  eq(date.monday_of("2026-01-04"), "2025-12-29")
  eq(date.monday_of("2026-01-05"), "2026-01-05")
end

T["monday_of"]["handles DST-change weeks"] = function()
  -- `make test` runs with TZ=America/New_York: DST starts 2026-03-08, ends 2026-11-01.
  local t = os.date("*t", os.time({ year = 2026, month = 7, day = 1, hour = 12 }))
  if not t.isdst then
    MiniTest.skip("TZ has no DST; run via `make test` (TZ=America/New_York)")
  end
  eq(date.monday_of("2026-03-08"), "2026-03-02")
  eq(date.monday_of("2026-03-09"), "2026-03-09")
  eq(date.monday_of("2026-03-15"), "2026-03-09")
  eq(date.monday_of("2026-11-01"), "2026-10-26")
  eq(date.monday_of("2026-11-02"), "2026-11-02")
  eq(date.add_days("2026-03-07", 1), "2026-03-08")
  eq(date.add_days("2026-03-08", 1), "2026-03-09")
  eq(date.add_days("2026-11-01", 1), "2026-11-02")
end

T["monday_of"]["is consistent for every day of 2026"] = function()
  local d = "2026-01-01"
  while d < "2027-01-01" do
    local monday = date.monday_of(d)
    eq(date.weekday(monday), 1)
    eq(date.add_days(monday, date.weekday(d) - 1), d)
    d = date.add_days(d, 1)
  end
end

T["week_start_of honours a custom start day"] = function()
  eq(date.week_start_of("2026-10-14", 7), "2026-10-11") -- Sunday-start weeks
  eq(date.week_start_of("2026-10-11", 7), "2026-10-11")
end

T["iso_week"] = function()
  eq(date.iso_week("2026-10-14"), "2026-W42")
  eq(date.iso_week("2026-01-01"), "2026-W01")
  eq(date.iso_week("2027-01-01"), "2026-W53")
  eq(date.iso_week("2024-12-30"), "2025-W01")
end

T["workdays"] = MiniTest.new_set()

T["workdays"]["prev/next skip the weekend"] = function()
  eq(date.prev_workday("2026-10-12"), "2026-10-09") -- Mon -> Fri
  eq(date.next_workday("2026-10-09"), "2026-10-12") -- Fri -> Mon
  eq(date.prev_workday("2026-10-14"), "2026-10-13")
  eq(date.next_workday("2026-10-17"), "2026-10-19") -- Sat -> Mon
  eq(date.is_workday("2026-10-17"), false)
end

T["workdays"]["honour custom workdays"] = function()
  local mwf = { 1, 3, 5 }
  eq(date.next_workday("2026-10-12", mwf), "2026-10-14")
  eq(date.prev_workday("2026-10-12", mwf), "2026-10-09")
end

T["workdays"]["raise on empty workdays"] = function()
  MiniTest.expect.error(function()
    date.next_workday("2026-10-12", {})
  end, "empty")
end

T["resolve_due adds weekday names: the next one, today included"] = function()
  local thu = "2026-10-15"
  eq(date.resolve_due("fri", thu), "2026-10-16")
  eq(date.resolve_due("Friday", thu), "2026-10-16")
  eq(date.resolve_due("thu", thu), thu)
  eq(date.resolve_due("wed", thu), "2026-10-21")
  eq(date.resolve_due("+3d", thu), "2026-10-18") -- everything resolve takes
  eq(date.resolve_due("mo", thu), nil) -- too short to tell
  eq(date.resolve_due("someday", thu), nil)
  eq(date.resolve("fri", thu), nil) -- search filters keep their meaning
end

return T

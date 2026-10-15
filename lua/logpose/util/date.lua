--- Date helpers. Dates are ISO `YYYY-MM-DD` strings everywhere.
--- All arithmetic is anchored at 12:00 local time so DST changes never shift a day.
local M = {}

local WEEKDAY_NAMES = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local DEFAULT_WORKDAYS = { 1, 2, 3, 4, 5 }

--- Clock source; tests replace this to freeze "now".
---@return integer
M._now = function()
  return os.time()
end

---@param y integer
---@param m integer
---@param d integer
---@return integer
local function noon(y, m, d)
  return os.time({ year = y, month = m, day = d, hour = 12, min = 0, sec = 0 })
end

---@param t integer
---@return string
local function to_iso(t)
  return os.date("%Y-%m-%d", t) --[[@as string]]
end

--- Parse an ISO date. Returns nil for malformed or impossible dates (e.g. 2026-02-30).
---@param s string
---@return integer? y, integer? m, integer? d
function M.parse_iso(s)
  if type(s) ~= "string" then
    return nil
  end
  local ys, ms, ds = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not ys then
    return nil
  end
  local y, m, d = tonumber(ys), tonumber(ms), tonumber(ds)
  if m < 1 or m > 12 or d < 1 or d > 31 then
    return nil
  end
  -- os.time normalises overflow (Feb 30 -> Mar 2); a round-trip catches it.
  if to_iso(noon(y, m, d)) ~= s then
    return nil
  end
  return y, m, d
end

---@param s string
---@return boolean
function M.is_iso(s)
  return M.parse_iso(s) ~= nil
end

---@param iso string
---@return integer
local function time_of(iso)
  local y, m, d = M.parse_iso(iso)
  if not y then
    error(("logpose: invalid date %q (expected YYYY-MM-DD)"):format(tostring(iso)), 3)
  end
  return noon(y, m, d)
end

---@return string
function M.today()
  return to_iso(M._now())
end

--- Current local time as `HHMM`.
---@return string
function M.now_hhmm()
  return os.date("%H%M", M._now()) --[[@as string]]
end

---@param iso string
---@param n integer
---@return string
function M.add_days(iso, n)
  local y, m, d = M.parse_iso(iso)
  if not y then
    time_of(iso) -- raises a consistent error
  end
  return to_iso(noon(y, m, d + n))
end

--- ISO weekday: Monday = 1 … Sunday = 7.
---@param iso string
---@return integer
function M.weekday(iso)
  local wday = os.date("*t", time_of(iso)).wday -- Sunday = 1
  return (wday + 5) % 7 + 1
end

--- English weekday name (locale-independent).
---@param iso string
---@return string
function M.weekday_name(iso)
  return WEEKDAY_NAMES[M.weekday(iso)]
end

--- Start of the week containing `iso`.
---@param iso string
---@param week_start? integer ISO weekday the week starts on (default 1, Monday)
---@return string
function M.week_start_of(iso, week_start)
  week_start = week_start or 1
  local offset = (M.weekday(iso) - week_start) % 7
  return M.add_days(iso, -offset)
end

---@param iso string
---@return string
function M.monday_of(iso)
  return M.week_start_of(iso, 1)
end

--- ISO-8601 week label, e.g. `2026-W42`.
---@param iso string
---@return string
function M.iso_week(iso)
  local thursday = M.add_days(iso, 4 - M.weekday(iso))
  local y = M.parse_iso(thursday)
  local yday = os.date("*t", time_of(thursday)).yday
  return ("%04d-W%02d"):format(y, math.floor((yday - 1) / 7) + 1)
end

---@param iso string
---@param workdays? integer[]
---@return boolean
function M.is_workday(iso, workdays)
  local wd = M.weekday(iso)
  for _, w in ipairs(workdays or DEFAULT_WORKDAYS) do
    if w == wd then
      return true
    end
  end
  return false
end

---@param iso string
---@param step integer
---@param workdays? integer[]
---@return string
local function step_workday(iso, step, workdays)
  workdays = workdays or DEFAULT_WORKDAYS
  if #workdays == 0 then
    error("logpose: `workdays` is empty", 3)
  end
  local d = iso
  for _ = 1, 7 do
    d = M.add_days(d, step)
    if M.is_workday(d, workdays) then
      return d
    end
  end
  error("logpose: no workday found within a week", 3)
end

---@param iso string
---@param workdays? integer[]
---@return string
function M.prev_workday(iso, workdays)
  return step_workday(iso, -1, workdays)
end

---@param iso string
---@param workdays? integer[]
---@return string
function M.next_workday(iso, workdays)
  return step_workday(iso, 1, workdays)
end

return M

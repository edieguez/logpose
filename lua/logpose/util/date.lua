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

--- Whole days from `a` to `b` (negative if `b` is earlier).
---@param a string
---@param b string
---@return integer
function M.diff_days(a, b)
  return math.floor((time_of(b) - time_of(a)) / 86400 + 0.5)
end

--- Resolve a date expression relative to `today`: YYYY-MM-DD, today, yesterday, tomorrow,
--- +N/-N with d (days) or w (weeks), e.g. -7d, +2w. Returns nil if not a date.
---@param expr string
---@param today? string
---@return string?
function M.resolve(expr, today)
  if type(expr) ~= "string" then
    return nil
  end
  today = today or M.today()
  local e = expr:lower()
  if M.is_iso(e) then
    return e
  elseif e == "today" then
    return today
  elseif e == "yesterday" then
    return M.add_days(today, -1)
  elseif e == "tomorrow" then
    return M.add_days(today, 1)
  end
  local sign, n, unit = e:match("^([+-])(%d+)([dw])$")
  if sign then
    local days = tonumber(n) * (unit == "w" and 7 or 1)
    return M.add_days(today, sign == "-" and -days or days)
  end
  return nil
end

M.MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

--- A date in short words: "Fri 16 Oct", with the year when it isn't this year.
---@param iso string
---@param today? string
---@return string
function M.short(iso, today)
  today = today or M.today()
  local y, m, d = iso:match("^(%d+)-(%d+)-(%d+)$")
  local out = ("%s %d %s"):format(M.weekday_name(iso):sub(1, 3), tonumber(d), M.MONTHS[tonumber(m)])
  return y == today:sub(1, 4) and out or (out .. " " .. y)
end

--- How long ago a moment was, in words: "just now", "5 min ago", "3h ago", "yesterday",
--- "4 days ago".
---@param t integer  seconds (os.time)
---@param now? integer
---@return string
function M.ago(t, now)
  local d = math.max(0, (now or os.time()) - t)
  if d < 60 then
    return "just now"
  elseif d < 3600 then
    return ("%d min ago"):format(math.floor(d / 60))
  elseif d < 86400 then
    return ("%dh ago"):format(math.floor(d / 3600))
  end
  local days = math.floor(d / 86400)
  return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

--- How far a date is from today: "today", "tomorrow", "yesterday", "in 5 days", "3 days ago".
---@param iso string
---@param today? string
---@return string
function M.relative(iso, today)
  local d = M.diff_days(today or M.today(), iso)
  if d == 0 then
    return "today"
  elseif d == 1 then
    return "tomorrow"
  elseif d == -1 then
    return "yesterday"
  end
  return d > 1 and ("in %d days"):format(d) or ("%d days ago"):format(-d)
end

--- How a due date reads everywhere it's shown, and how urgent it is: "overdue 2d" (overdue),
--- "due today" / "due tomorrow" (soon), "due Tue" within a week (week), "due 3 Nov" (later).
---@param iso string
---@param today? string
---@return string text, "overdue"|"soon"|"week"|"later" urgency
function M.due(iso, today)
  today = today or M.today()
  local d = M.diff_days(today, iso)
  if d < 0 then
    return ("overdue %dd"):format(-d), "overdue"
  elseif d == 0 then
    return "due today", "soon"
  elseif d == 1 then
    return "due tomorrow", "soon"
  elseif d < 7 then
    return "due " .. M.weekday_name(iso):sub(1, 3), "week"
  end
  local y, m, day = iso:match("^(%d+)-(%d+)-(%d+)$")
  local text = ("due %d %s"):format(tonumber(day), M.MONTHS[tonumber(m)])
  return y == today:sub(1, 4) and text or (text .. " " .. y), "later"
end

--- Weekday names, Monday first, for `M.resolve_due`.
M.WEEKDAYS = { "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" }

--- Resolve a due date: everything `M.resolve` understands, plus a weekday name or its first
--- three letters (`fri`), meaning the next one from today (today included).
---@param expr string
---@param today? string
---@return string?
function M.resolve_due(expr, today)
  local iso = M.resolve(expr, today)
  if iso or type(expr) ~= "string" then
    return iso
  end
  local e = expr:lower()
  if #e < 3 then
    return nil
  end
  today = today or M.today()
  for i, name in ipairs(M.WEEKDAYS) do
    if vim.startswith(name, e) then
      return M.add_days(today, (i - M.weekday(today)) % 7)
    end
  end
  return nil
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

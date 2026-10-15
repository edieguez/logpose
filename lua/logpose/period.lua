--- Periods used to group dated sections: calendar weeks (any start day) or sprints
--- (fixed length, counted from an anchor date).
local config = require("logpose.config")
local date = require("logpose.util.date")
local text = require("logpose.util.text")

local M = {}

---@class logpose.Period
---@field kind "week"|"sprint"
---@field key string     filename part: the week's start date, or the sprint name
---@field start string   first day (YYYY-MM-DD)
---@field finish string  last day (YYYY-MM-DD)
---@field label string   "week of 2026-10-05" / "sprint-42 (2026-10-01 – 2026-10-14)"
---@field number? integer sprint number

--- Sprint containing `iso`.
---@param iso string
---@param sprint table period.sprint options (anchor required)
---@return logpose.Period
function M.sprint_of(iso, sprint)
  local len = sprint.length_days
  local idx = math.floor(date.diff_days(sprint.anchor, iso) / len)
  local start = date.add_days(sprint.anchor, idx * len)
  local finish = date.add_days(start, len - 1)
  local n = sprint.first_number + idx
  local name = text.substitute(sprint.name, { n = tostring(n) })
  return {
    kind = "sprint",
    key = name,
    start = start,
    finish = finish,
    number = n,
    label = ("%s (%s – %s)"):format(name, start, finish),
  }
end

--- Week containing `iso`.
---@param iso string
---@param week_start integer
---@return logpose.Period
function M.week_of(iso, week_start)
  local start = date.week_start_of(iso, week_start)
  return {
    kind = "week",
    key = start,
    start = start,
    finish = date.add_days(start, 6),
    label = "week of " .. start,
  }
end

--- Period containing `iso`, per `period` options (default: the configured ones).
---@param iso string
---@param opts? table
---@return logpose.Period
function M.of(iso, opts)
  opts = opts or config.get().period
  if opts.kind == "sprint" then
    return M.sprint_of(iso, opts.sprint)
  end
  return M.week_of(iso, opts.week_start)
end

--- Resolve `week:<spec>` / `sprint:<spec>` relative to `today`.
--- spec: current | -N | +N (periods back/forward) | YYYY-MM-DD (the period containing it) |
--- N (sprint number, sprints only).
---@param kind "week"|"sprint"
---@param spec string
---@param today string
---@param opts? table period options (default: configured)
---@return logpose.Period? period, string? err
function M.resolve(kind, spec, today, opts)
  opts = opts or config.get().period
  if kind == "sprint" and not opts.sprint.anchor then
    return nil, "logpose: sprint: needs `period.sprint.anchor` in setup()"
  end
  local function of(iso)
    if kind == "sprint" then
      return M.sprint_of(iso, opts.sprint)
    end
    return M.week_of(iso, opts.week_start)
  end
  local step = kind == "sprint" and opts.sprint.length_days or 7
  spec = spec:lower()
  if spec == "current" or spec == "this" then
    return of(today)
  end
  if date.is_iso(spec) then
    return of(spec)
  end
  local sign, n = spec:match("^([+-])(%d+)$")
  if sign then
    local offset = tonumber(n) * (sign == "-" and -1 or 1)
    return of(date.add_days(of(today).start, offset * step))
  end
  local num = spec:match("^(%d+)$")
  if num and kind == "sprint" then
    local idx = tonumber(num) - opts.sprint.first_number
    return of(date.add_days(opts.sprint.anchor, idx * step))
  end
  return nil,
    ("logpose: %s: expects current, -N, +N, a date%s; got %q"):format(
      kind,
      kind == "sprint" and " or a sprint number" or "",
      spec
    )
end

--- Sprint name for `iso` when a sprint anchor is configured, else "".
---@param iso string
---@return string
function M.sprint_name(iso)
  local sprint = config.get().period.sprint
  if not sprint.anchor then
    return ""
  end
  return M.sprint_of(iso, sprint).key
end

return M

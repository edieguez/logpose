--- Local, opt-in usage counts: which commands you use, per day. Nothing leaves your machine;
--- no note content, paths or arguments are stored — only the command and, for a few commands,
--- the scope/mode keyword (e.g. "find tasks").
local config = require("logpose.config")
local fs = require("logpose.util.fs")

local M = {}

--- Commands whose first argument is a fixed keyword worth counting separately.
local KEYWORDS = {
  find = {
    "notes",
    "daily",
    "meetings",
    "topics",
    "archives",
    "tasks",
    "decisions",
    "blockers",
    "tags",
    "projects",
    "people",
  },
  actions = { "open", "mine", "overdue", "all" },
  report = { "week", "sprint" },
  daily = { "today", "prev", "next" },
  board = { "move", "done", "block", "reorder", "add", "open", "delete", "peek" }, -- recorded by the board's keys
}

M.throttle_ms = 60 * 1000
M._data = nil
M._dirty = false
M._last_flush = -math.huge -- the first event is written right away

---@return string
function M.path()
  return fs.join(vim.fn.stdpath("data") --[[@as string]], "logpose", "usage.json")
end

---@return table
local function load()
  if M._data then
    return M._data
  end
  local content = fs.read_file(M.path())
  local ok, data = pcall(vim.json.decode, content or "")
  M._data = (ok and type(data) == "table" and type(data.days) == "table") and data or { version = 1, days = {} }
  return M._data
end

--- Event key for a command: "find tasks", "meeting", "archive"…
---@param name string
---@param args string[]
---@return string
function M.key(name, args)
  local kw = KEYWORDS[name]
  if kw and args[1] and vim.tbl_contains(kw, args[1]) then
    return name .. " " .. args[1]
  end
  if name == "meeting" and args[1] then
    local spec = config.get().meeting_types[args[1]]
    if spec then
      return "meeting " .. args[1]
    end
  end
  return name
end

--- Write pending counts, dropping days older than the retention window.
function M.flush()
  if not M._data or not M._dirty then
    return
  end
  local cutoff =
    require("logpose.util.date").add_days(require("logpose.util.date").today(), -config.get().telemetry.retention_days)
  for day in pairs(M._data.days) do
    if day < cutoff then
      M._data.days[day] = nil
    end
  end
  local ok = fs.write_file(M.path(), vim.json.encode(M._data) .. "\n")
  if ok then
    M._dirty = false
    M._last_flush = (vim.uv or vim.loop).now()
  end
end

--- Count one use of a command (no-op unless `telemetry.enabled`).
---@param name string subcommand
---@param args string[]
---@param ok boolean
function M.record(name, args, ok)
  if not config.get().telemetry.enabled then
    return
  end
  local data = load()
  local day = require("logpose.util.date").today()
  local key = M.key(name, args)
  data.days[day] = data.days[day] or {}
  local entry = data.days[day][key] or { ok = 0, err = 0 }
  if ok then
    entry.ok = entry.ok + 1
  else
    entry.err = entry.err + 1
  end
  data.days[day][key] = entry
  M._dirty = true
  if (vim.uv or vim.loop).now() - M._last_flush >= M.throttle_ms then
    M.flush()
  end
end

--- Usage summary over the last `days` days.
---@param days integer
---@return string[] lines
function M.render(days)
  M.flush()
  local data = load()
  local date = require("logpose.util.date")
  local today = date.today()
  local since = date.add_days(today, -(days - 1))
  local week_ago, two_weeks_ago = date.add_days(today, -6), date.add_days(today, -13)
  local totals, recent, previous, errors = {}, {}, {}, {}
  for day, events in pairs(data.days) do
    for key, e in pairs(events) do
      local n = e.ok + e.err
      if day >= since then
        totals[key] = (totals[key] or 0) + n
        errors[key] = (errors[key] or 0) + e.err
      end
      if day >= week_ago then
        recent[key] = (recent[key] or 0) + n
      elseif day >= two_weeks_ago then
        previous[key] = (previous[key] or 0) + n
      end
    end
  end
  local keys = vim.tbl_keys(totals)
  table.sort(keys, function(a, b)
    if totals[a] ~= totals[b] then
      return totals[a] > totals[b]
    end
    return a < b
  end)
  local out = {
    ("# logpose usage, last %d days"):format(days),
    "",
    ("Stored locally in %s"):format(vim.fn.fnamemodify(M.path(), ":~")),
    "",
    "| command | uses | last 7 days | previous 7 | errors |",
    "|---|---:|---:|---:|---:|",
  }
  for _, k in ipairs(keys) do
    table.insert(
      out,
      ("| %s | %d | %d | %d | %d |"):format(k, totals[k], recent[k] or 0, previous[k] or 0, errors[k] or 0)
    )
  end
  if #keys == 0 then
    table.insert(out, "| (nothing recorded yet) | | | | |")
  end
  local used = {}
  for _, k in ipairs(keys) do
    used[vim.split(k, " ")[1]] = true
  end
  local never = vim.tbl_filter(function(name)
    return not used[name] and name ~= "stats"
  end, require("logpose.commands").names())
  table.insert(out, "")
  table.insert(out, "## Not used in this period")
  table.insert(out, #never > 0 and table.concat(never, ", ") or "(every command was used)")
  return out
end

---@param opts logpose.CommandOpts
function M.command(opts)
  if opts.bang then
    M._data, M._dirty = { version = 1, days = {} }, false
    os.remove(M.path())
    vim.notify("logpose: usage stats reset", vim.log.levels.INFO)
    return
  end
  if not config.get().telemetry.enabled and not fs.exists(M.path()) then
    vim.notify(
      "logpose: usage stats are off; enable with setup({ telemetry = { enabled = true } })",
      vim.log.levels.INFO
    )
    return
  end
  local days = tonumber(opts.args[1] or "30")
  if not days or days < 1 then
    error("logpose: usage :Logpose stats[!] [days]", 0)
  end
  local lines = M.render(math.floor(days))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  pcall(vim.api.nvim_buf_set_name, buf, "logpose://stats")
  vim.cmd(("botright %dsplit"):format(math.min(#lines + 1, 25)))
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
end

function M.setup_autocmd()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("logpose_telemetry", { clear = true }),
    callback = function()
      pcall(M.flush)
    end,
  })
end

return M

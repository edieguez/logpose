--- `require("logpose").statusline()`: the board at a glance for lualine and friends, e.g.
--- "acme · 2 in progress · 1 blocked · sprint-43 2/10". Empty outside a journal setup.
local M = {}

--- Seconds a computed line is reused (logpose's own writes refresh it at once).
M.ttl_ms = 5000

local cache = {} ---@type table<string, { at: integer, gen: integer, text: string }>

---@class logpose.StatuslineOpts
---@field project? boolean  the active project (default true)
---@field tasks? boolean    in progress / blocked counts (default true)
---@field period? boolean   current sprint or week, with the workday (default true)
---@field separator? string default " · "

--- Workday `n` of `total` in the current period.
---@param p logpose.Period
---@param today string
---@return integer n, integer total
local function workday(p, today)
  local date = require("logpose.util.date")
  local workdays = require("logpose.config").get().workdays
  local n, total, d = 0, 0, p.start
  while d <= p.finish do
    if date.is_workday(d, workdays) then
      total = total + 1
      if d <= today then
        n = n + 1
      end
    end
    d = date.add_days(d, 1)
  end
  return math.max(n, 1), total
end

---@param root string
---@param project? string
---@param opts logpose.StatuslineOpts
---@return string
local function compute(root, project, opts)
  local config = require("logpose.config")
  local cfg = config.get()
  local parts = {}
  if opts.project ~= false and project then
    table.insert(parts, project)
  end
  if opts.tasks ~= false then
    if cfg.tasks.mode == "files" then
      local doing, blocked = 0, 0
      for _, t in ipairs(require("logpose.taskfile").list(root)) do
        local mine = not project or t.project == project or vim.tbl_contains(t.tags, project)
        if mine and t.status ~= cfg.board.done then
          if t.status == cfg.board.start then
            doing = doing + 1
          end
          if t.blocked then
            blocked = blocked + 1
          end
        end
      end
      if doing > 0 then
        table.insert(parts, ("%d %s"):format(doing, require("logpose.taskfile").label(cfg.board.start):lower()))
      end
      if blocked > 0 then
        table.insert(parts, ("%d blocked"):format(blocked))
      end
    else
      local open = 0
      for _, l in ipairs(require("logpose.util.fs").read_lines(config.path("inbox", root)) or {}) do
        local t = require("logpose.tasks").parse_task(l)
        if t and not t.checked then
          open = open + 1
        end
      end
      if open > 0 then
        table.insert(parts, ("%d in INBOX"):format(open))
      end
    end
  end
  if opts.period ~= false then
    local today = require("logpose.util.date").today()
    local ok, p = pcall(require("logpose.period").of, today)
    if ok and p then
      local n, total = workday(p, today)
      local name = p.kind == "sprint" and p.key or "week"
      table.insert(parts, ("%s %d/%d"):format(name, n, total))
    end
  end
  return table.concat(parts, opts.separator or " · ")
end

--- The status text (cached; cheap enough to call on every redraw).
---@param opts? logpose.StatuslineOpts
---@return string
function M.get(opts)
  opts = opts or {}
  -- Keyed by buffer and cwd, so the journal and project lookups only run when it's stale.
  local key = table.concat({ vim.api.nvim_get_current_buf(), vim.fn.getcwd(), vim.inspect(opts) }, "\0")
  local now = (vim.uv or vim.loop).now()
  local gen = require("logpose.index").generation
  local hit = cache[key]
  if hit and hit.gen == gen and now - hit.at < M.ttl_ms then
    return hit.text
  end
  local ok, text = pcall(function()
    local root = require("logpose.config").resolve_root()
    if not root then
      return ""
    end
    return compute(root, require("logpose.project").resolve(root), opts)
  end)
  text = ok and text or ""
  cache[key] = { at = now, gen = gen, text = text }
  return text
end

function M.clear()
  cache = {}
end

return M

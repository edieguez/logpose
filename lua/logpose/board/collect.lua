--- Which cards the board shows, and in which column and order.
local config = require("logpose.config")
local date = require("logpose.util.date")
local taskfile = require("logpose.taskfile")

local M = {}

--- First day whose Done tasks are still shown.
---@param today string
---@return string
local function done_since(today)
  local window = config.get().board.done_window
  if window == "period" then
    return require("logpose.period").of(today).start
  end
  return date.add_days(today, -(window - 1))
end

---@param a logpose.Item
---@param b logpose.Item
local function card_order(a, b)
  local oa, ob = a.order or math.huge, b.order or math.huge
  if oa ~= ob then
    return oa < ob
  end
  local da, db = a.due or "9999", b.due or "9999"
  if da ~= db then
    return da < db
  end
  local ca, cb = a.created or "", b.created or ""
  if ca ~= cb then
    return ca < cb
  end
  return a.file < b.file
end

--- Task items on the board, by column.
---@param root string
---@param opts { project?: string, filter?: string, today?: string, hidden?: table<string, boolean> }
---@return { key: string, label: string, cards: logpose.Item[] }[]
function M.collect(root, opts)
  local index = require("logpose.index")
  local query = require("logpose.query")
  local today = opts.today or date.today()
  local q = query.parse(query.split(opts.filter or ""), today, true)
  local cfg = config.get()
  local orders, since_of = {}, {}
  for _, t in ipairs(taskfile.list(root)) do
    orders[t.path] = t.order
    since_of[t.path] = t.since
  end
  local columns, by_key = {}, {}
  for _, c in ipairs(taskfile.columns()) do
    local col = { key = c.key, label = c.label, cards = {} }
    table.insert(columns, col)
    by_key[c.key] = col
  end
  local since = done_since(today)
  for _, it in ipairs(index.build(root)) do
    if it.kind == "note" and it.note_type == "task" and not it.archived then
      local in_scope
      if opts.project then
        in_scope = it.project == opts.project or vim.tbl_contains(it.tags, opts.project)
      else
        in_scope = not (it.project and opts.hidden and opts.hidden[it.project])
      end
      local recent = it.status ~= cfg.board.done or not it.done_date or it.done_date >= since
      if in_scope and recent and query.match(it, q) then
        it.order = orders[it.file]
        it.since = since_of[it.file]
        local col = by_key[it.status] or by_key[cfg.tasks.capture_status]
        table.insert(col.cards, it)
      end
    end
  end
  for _, col in ipairs(columns) do
    table.sort(col.cards, card_order)
  end
  return columns
end

return M

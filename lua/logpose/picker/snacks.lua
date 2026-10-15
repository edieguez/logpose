--- snacks.picker backend.
local M = {}

---@param items logpose.PickItem[]
---@return table[] entries, boolean has_preview
local function entries(items)
  local out, has_preview = {}, false
  for i, it in ipairs(items) do
    has_preview = has_preview or it.file ~= nil or it.preview ~= nil
    out[i] = {
      idx = i,
      text = it.display,
      file = it.file,
      pos = it.file and { it.lnum or 1, 0 } or nil,
      -- "file" shows the file at `pos`; a table shows logpose's own preview text.
      preview = it.file and "file" or (it.preview and { text = it.preview, ft = "markdown" }) or nil,
      value = it,
    }
  end
  return out, has_preview
end

---@param opts logpose.PickOpts
local function confirm(opts)
  return function(picker, item)
    picker:close()
    if item then
      opts.on_choice(item.value)
    end
  end
end

function M.pick(items, opts)
  local list, has_preview = entries(items)
  require("snacks").picker.pick({
    title = opts.prompt,
    items = list,
    format = "text",
    preview = has_preview and "preview" or "none",
    layout = not has_preview and { preset = "select" } or nil,
    sort = { fields = { "score:desc", "idx" } }, -- keep logpose's order when the query is empty
    confirm = confirm(opts),
  })
end

--- The prompt is logpose's query: every change re-runs `opts.items`. <C-g> switches to
--- fuzzy-filtering the current results, as in snacks' own live pickers.
function M.live(opts)
  require("snacks").picker.pick({
    title = opts.prompt,
    finder = function(_, ctx)
      return (entries(opts.items(ctx.filter.search)))
    end,
    live = true,
    supports_live = true,
    search = opts.query,
    format = "text",
    preview = "preview",
    sort = { fields = { "score:desc", "idx" } },
    confirm = confirm(opts),
  })
end

function M.grep(opts)
  require("snacks").picker.grep({ cwd = opts.cwd, dirs = { opts.cwd }, search = opts.text })
end

return M

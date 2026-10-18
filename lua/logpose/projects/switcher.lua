--- The quick switcher behind `:Logpose project` and `P` on the board: projects in the picker,
--- the active one first, then the ones you switched to recently, each previewing its details.
local project = require("logpose.project")
local ui = require("logpose.util.ui")
local summary = require("logpose.projects.summary")
local manager = require("logpose.projects.manager")

local M = {}

--- The quick switcher: projects in the picker, the ones you switched to recently first, each
--- previewing what's going on in it. Choosing one makes it the active project.
---@param root string
---@param opts? { on_switch?: fun(name?: string) }
function M.switch(root, opts)
  opts = opts or {}
  local list = vim.tbl_filter(function(e)
    return not e.archived
  end, summary.stats(root))
  local current = project.resolve(root)
  local rank = {}
  for i, name in ipairs(project.recent()) do
    rank[name] = i
  end
  -- the active project first, then recently switched to, then by activity (already sorted)
  local pos = {}
  for i, e in ipairs(list) do
    pos[e] = i
  end
  table.sort(list, function(a, b)
    if (a.name == current) ~= (b.name == current) then
      return a.name == current
    end
    local ra, rb = rank[a.name] or math.huge, rank[b.name] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return pos[a] < pos[b]
  end)
  local width = 0
  for _, e in ipairs(list) do
    width = math.max(width, vim.fn.strdisplaywidth(e.title))
  end
  local items = {}
  for _, e in ipairs(list) do
    local line = {}
    for _, c in ipairs(summary.summary(e)) do
      table.insert(line, c[1])
    end
    local preview = { "# " .. e.title, "" }
    vim.list_extend(preview, { table.concat(line), "" })
    for _, d in ipairs(summary.details(e)) do
      local t = {}
      for _, c in ipairs(d.chunks) do
        table.insert(t, c[1])
      end
      table.insert(preview, table.concat(t))
    end
    if e.last then
      vim.list_extend(preview, { "", "Last change: " .. e.last })
    end
    table.insert(items, {
      display = ("%s %s%s  %s"):format(
        e.name == current and "●" or " ",
        e.title,
        string.rep(" ", width - vim.fn.strdisplaywidth(e.title)),
        table.concat(line)
      ),
      preview = table.concat(preview, "\n"),
      name = e.name,
    })
  end
  table.insert(items, { display = "+ New project…", preview = "Create a project page and switch to it.", new = true })
  table.insert(items, {
    display = "  Auto-detect",
    preview = "Unpin the project: logpose follows the repo you are in.",
    clear = true,
  })
  local function done(name)
    if opts.on_switch then
      opts.on_switch(name)
    end
  end
  require("logpose.picker").pick(items, {
    prompt = "Switch project",
    on_choice = ui.safely(function(item)
      if item.clear then
        project.set(nil)
        return done(nil)
      end
      if not item.new then
        project.switch_to(item.name)
        return done(item.name)
      end
      manager.ask("New project: ", nil, function(p, typed)
        if not project.pages(root)[p] then
          project.add(root, typed)
        end
        project.switch_to(p)
        done(p)
      end)
    end),
  })
end

return M

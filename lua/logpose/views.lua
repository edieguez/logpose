--- Saved searches: `:Logpose view [name]` runs `:Logpose find <views[name]>`.
local config = require("logpose.config")
local ui = require("logpose.util.ui")

local M = {}

---@return string[]
function M.names()
  local names = vim.tbl_keys(config.get().views)
  table.sort(names)
  return names
end

---@param name string
function M.run(name)
  local view = config.get().views[name]
  if not view then
    local names = M.names()
    error(
      ("logpose: unknown view %q. %s"):format(
        name,
        #names > 0 and ("Valid: " .. table.concat(names, ", ")) or "Define views in setup({ views = { … } })"
      ),
      0
    )
  end
  require("logpose.search").find_command({ args = vim.split(vim.trim(view), "%s+", { trimempty = true }) })
end

---@param opts logpose.CommandOpts
function M.command(opts)
  if opts.args[1] then
    return M.run(opts.args[1])
  end
  local names = M.names()
  if #names == 0 then
    require("logpose.util.ui").notify(
      'logpose: no views; define them in setup({ views = { name = "find args" } })',
      vim.log.levels.INFO
    )
    return
  end
  vim.ui.select(
    names,
    {
      prompt = "View",
      format_item = function(name)
        return ("%s  (%s)"):format(name, config.get().views[name])
      end,
    },
    ui.safely(function(choice)
      if choice then
        M.run(choice)
      end
    end)
  )
end

function M.complete(_, args)
  return #args == 0 and M.names() or {}
end

return M

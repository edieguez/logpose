--- Picker adapter. logpose builds and filters the items; a backend only displays them.
---   pick(items, { prompt, on_choice })   items: { display, file?, lnum?, ... }
---   grep({ cwd, text })                  live grep in a directory
local M = {}

M.backends = { "snacks", "fzf_lua", "telescope", "select" }

local probes = {
  snacks = function()
    local ok, snacks = pcall(require, "snacks")
    return ok and type(snacks) == "table" and snacks.picker ~= nil
  end,
  fzf_lua = function()
    return (pcall(require, "fzf-lua"))
  end,
  telescope = function()
    return (pcall(require, "telescope"))
  end,
  select = function()
    return true
  end,
}

--- Backend that will be used, honouring a forced `name`.
---@param name? string "auto" or a backend name
---@return string backend, string? warning
function M.detect(name)
  if name and name ~= "auto" then
    if not probes[name] then
      return "select", ("unknown picker %q; using vim.ui.select"):format(name)
    end
    if probes[name]() then
      return name
    end
    return "select", ("picker %q is not installed; using vim.ui.select"):format(name)
  end
  for _, backend in ipairs(M.backends) do
    if probes[backend]() then
      return backend
    end
  end
  return "select"
end

---@return table backend module
local function backend()
  local name = M.detect(require("logpose.config").get().picker)
  return require("logpose.picker." .. name)
end

--- Open `item.file` at `item.lnum`.
---@param item { file?: string, lnum?: integer }
function M.open(item)
  if not item or not item.file then
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(item.file))
  if item.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, 0 })
  end
end

---@class logpose.PickItem
---@field display string
---@field file? string
---@field lnum? integer

---@class logpose.PickOpts
---@field prompt string
---@field cwd? string  base for relative paths (the journal root)
---@field on_choice? fun(item: logpose.PickItem)

---@param items logpose.PickItem[]
---@param opts logpose.PickOpts
function M.pick(items, opts)
  opts = vim.tbl_extend("keep", opts, { on_choice = M.open })
  backend().pick(items, opts)
end

---@param opts { cwd: string, text?: string }
function M.grep(opts)
  backend().grep(opts)
end

return M

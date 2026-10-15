--- Picker adapter. F0 only detects the backend; F4 adds the picking API.
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

return M

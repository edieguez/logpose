--- UI helpers shared by commands.
local M = {}

---@param err any
---@return string
function M.message(err)
  local msg = type(err) == "string" and err or vim.inspect(err)
  if not msg:find("^logpose:") then
    msg = "logpose: " .. msg
  end
  return msg
end

--- Wrap a callback (e.g. for vim.ui.input/select) so errors become notifications.
---@param fn function
---@return function
function M.safely(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      vim.notify(M.message(err), vim.log.levels.ERROR)
    end
  end
end

return M

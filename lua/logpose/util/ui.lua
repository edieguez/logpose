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

--- Whether a notifier plugin that shows titles (snacks, nvim-notify, noice) is in use.
---@return boolean
function M.titled_notifier()
  return package.loaded["snacks.notifier"] ~= nil or package.loaded["notify"] ~= nil or package.loaded["noice"] ~= nil
end

--- Notify with a "logpose" title. With a notifier that shows titles the "logpose: " prefix is
--- dropped (the title says it); with plain messages it's kept, so you know where it came from.
---@param msg string
---@param level? integer vim.log.levels
function M.notify(msg, level)
  msg = tostring(msg)
  if M.titled_notifier() then
    msg = msg:gsub("^logpose:%s*", "")
    msg = msg:sub(1, 1):upper() .. msg:sub(2)
  end
  vim.notify(msg, level or vim.log.levels.INFO, { title = "logpose" })
end

--- Wrap a callback (e.g. for vim.ui.input/select) so errors become notifications.
---@param fn function
---@return function
function M.safely(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      M.notify(M.message(err), vim.log.levels.ERROR)
    end
  end
end

return M

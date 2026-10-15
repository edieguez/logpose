--- nvim-cmp source for `[[` note links. Registered as "logpose" by require("logpose").setup()
--- when nvim-cmp is installed; add { name = "logpose" } to your markdown sources.
local M = {}

function M.new()
  return setmetatable({}, { __index = M })
end

function M:is_available()
  return vim.bo.filetype == "markdown" and require("logpose.config").resolve_root() ~= nil
end

function M:get_trigger_characters()
  return { "[" }
end

function M:get_keyword_pattern()
  return [=[\[\[[^\]]*]=]
end

function M:complete(params, callback)
  local row, col = params.context.cursor.row - 1, params.context.cursor.col - 1
  local items = require("logpose.links").complete_items(
    params.context.cursor_line,
    col,
    row,
    vim.api.nvim_buf_get_name(params.context.bufnr)
  )
  callback({ items = items, isIncomplete = false })
end

--- Register with nvim-cmp if it's installed. Returns true when registered.
function M.register()
  local ok, cmp = pcall(require, "cmp")
  if not ok or type(cmp.register_source) ~= "function" then
    return false
  end
  cmp.register_source("logpose", M.new())
  return true
end

return M

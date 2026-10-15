--- blink.cmp source for `[[` note links. Add to your blink config:
---   sources = { per_filetype = { markdown = { inherit_defaults = true, "logpose" } },
---               providers = { logpose = { name = "logpose", module = "logpose.completion.blink" } } }
local M = {}

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  return vim.bo.filetype == "markdown" and require("logpose.config").resolve_root() ~= nil
end

function M:get_trigger_characters()
  return { "[" }
end

function M:get_completions(ctx, callback)
  local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local items = require("logpose.links").complete_items(ctx.line, col, row, vim.api.nvim_buf_get_name(ctx.bufnr))
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
  return function() end
end

return M

--- blink.cmp source for journal notes: `[[` links, people in `attendees:`/`with:`, `@` mentions
--- (see `logpose.completion`). Add to your blink config:
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
  return require("logpose.completion").TRIGGERS
end

function M:get_completions(ctx, callback)
  local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local items = require("logpose.completion").items(ctx.line, col, row, ctx.bufnr)
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
  return function() end
end

return M

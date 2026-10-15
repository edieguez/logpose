--- logpose.nvim — daily notes, meeting notes and sprint archives for Scrum/Kanban work.
local M = {}

--- Configure logpose. Optional: commands work with defaults.
---@param opts? table
function M.setup(opts)
  require("logpose.config").setup(opts)
  require("logpose.completion.cmp").register() -- no-op without nvim-cmp
end

--- Active project for the current buffer/cwd, or nil (handy for statuslines).
---@return string?
function M.project()
  return require("logpose.project").current()
end

return M

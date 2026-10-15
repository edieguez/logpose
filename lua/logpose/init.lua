--- logpose.nvim — daily notes, meeting notes and sprint archives for Scrum/Kanban work.
local M = {}

--- Configure logpose. Optional: commands work with defaults.
---@param opts? table
function M.setup(opts)
  require("logpose.config").setup(opts)
end

return M

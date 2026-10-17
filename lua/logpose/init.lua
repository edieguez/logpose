--- logpose.nvim — daily notes, meeting notes and sprint archives for Scrum/Kanban work.
local M = {}

--- Configure logpose. Optional: commands work with defaults.
---@param opts? table
function M.setup(opts)
  require("logpose.config").setup(opts)
  require("logpose.completion.cmp").register() -- no-op without nvim-cmp
  require("logpose.keymaps").apply(require("logpose.config").get().keymaps)
end

--- Active project for the current buffer/cwd, or nil (handy for statuslines).
---@return string?
function M.project()
  return require("logpose.project").current()
end

--- The board at a glance, for your statusline: "acme · 2 in progress · 1 blocked · sprint-43 2/10".
--- lualine: `lualine_x = { function() return require("logpose").statusline() end }`
---@param opts? logpose.StatuslineOpts  project/tasks/period (booleans), separator
---@return string
function M.statusline(opts)
  return require("logpose.statusline").get(opts)
end

return M

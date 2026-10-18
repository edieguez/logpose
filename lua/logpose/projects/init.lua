--- Projects at a glance: `:Logpose projects` (the manager screen, `projects.manager`) and the
--- quick switcher behind `:Logpose project` (`projects.switcher`). Both show, per project, what
--- needs attention, from `projects.summary`. This module re-exports their functions.
local M = {}

for _, part in ipairs({
  require("logpose.projects.summary"),
  require("logpose.projects.manager"),
  require("logpose.projects.switcher"),
}) do
  for k, v in pairs(part) do
    M[k] = v
  end
end

return M

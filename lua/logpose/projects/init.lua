--- Projects at a glance: the manager screen (`projects.manager`), behind `:Logpose projects`,
--- `:Logpose project` without a name and `P` on the board. It shows, per project, what needs
--- attention, from `projects.summary`. This module re-exports their functions.
local M = {}

for _, part in ipairs({
  require("logpose.projects.summary"),
  require("logpose.projects.manager"),
}) do
  for k, v in pairs(part) do
    M[k] = v
  end
end

return M

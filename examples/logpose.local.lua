-- This computer's own logpose settings: a template. Copy it beside the file with your shared options (in
-- LazyVim, lua/plugins/logpose.local.lua) and add *.local.lua to your Neovim config's .gitignore, so each
-- computer keeps its own. lazy.nvim reads it after logpose.lua, so what you set here wins. Write only what
-- differs: tables merge key by key, lists replace the shared ones whole, and vim.NIL clears an option.
return {
  "edieguez/logpose",
  -- dir = "~/src/logpose", -- run a checkout of logpose on this computer
  -- enabled = false, -- no logpose on this computer
  opts = {
    -- root = "~/work/journal", -- this computer's journal, if it isn't the one :Logpose init chose
    -- me = "@ana", -- your handle here (action items, tasks assigned to you)
    -- projects = { paths = { ["~/work/acme-api"] = "acme" } }, -- repo folders that are a project here
    -- tickets = { url = "https://acme.atlassian.net/browse/{id}" }, -- the tracker gx opens tickets in
    -- people = { contacts = { slack = { label = "Slack", show = "@{value}", order = 2 } } }, -- the team's chat
    -- board = { icons = "nerd" }, -- this terminal has a Nerd Font
    -- telemetry = { enabled = false }, -- no usage counts on this computer
  },
}

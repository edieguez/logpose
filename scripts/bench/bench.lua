-- Times everyday logpose operations against a journal.
-- nvim --headless -u NONE -i NONE --cmd "set rtp^=$PWD" -l scripts/bench/bench.lua JOURNAL [REPO]
local root, repo = _G.arg[1], _G.arg[2]
vim.o.columns, vim.o.lines = 160, 45
vim.cmd("runtime plugin/logpose.lua")
vim.env.XDG_DATA_HOME = vim.fn.tempname()
require("logpose").setup({
  root = root,
  picker = "select",
  projects = { open_board = false },
  period = { kind = "sprint", sprint = { anchor = "2026-10-15", first_number = 43 } },
})
vim.notify = function() end
require("logpose.util.date")._now = function()
  return os.time({ year = 2026, month = 10, day = 15, hour = 10, min = 30 })
end
vim.ui.select = function(items, _, cb) end
vim.ui.input = function(_, cb) end
local uv = vim.uv or vim.loop
local index = require("logpose.index")
local results = {}
local function ms(fn)
  local t = uv.hrtime()
  fn()
  return (uv.hrtime() - t) / 1e6
end
--- Cold: caches cleared first. Warm: the median of 5 repeats.
local function bench(name, fn, opts)
  opts = opts or {}
  if opts.setup then
    opts.setup()
  end
  index.flush()
  pcall(function()
    require("logpose.statusline").clear()
  end)
  local cold = ms(fn)
  local warm = {}
  for _ = 1, 5 do
    if opts.setup then
      opts.setup()
    end
    if opts.reset then
      opts.reset()
    end
    index.forget_build() -- each run is a new command
    table.insert(warm, ms(fn))
  end
  table.sort(warm)
  local line = ("%-34s cold %8.1f ms   warm %8.1f ms"):format(name, cold, warm[3])
  table.insert(results, line)
  io.stdout:write(line, "\n")
end

vim.cmd("cd " .. root)
bench("index.build", function()
  index.build(root)
end)
bench("project.resolve (in the journal)", function()
  require("logpose.project").resolve(root)
end)
if repo then
  vim.cmd("edit " .. repo .. "/main.go")
  bench("project.resolve (in a repo)", function()
    require("logpose.project").resolve(root)
  end)
  bench("statusline (in a repo, uncached)", function()
    require("logpose.statusline").clear()
    require("logpose").statusline()
  end)
  vim.cmd("enew")
end
bench("completion :Logpose project", function()
  vim.fn.getcompletion("Logpose project ", "cmdline")
end)
bench("statusline (uncached)", function()
  require("logpose.statusline").clear()
  require("logpose").statusline()
end)
bench("search: find tasks open", function()
  require("logpose.search").find(root, "tasks", { "open" })
end)
local b
bench("board: open", function()
  b = require("logpose.board").open_board(root)
end)
bench("board: refresh", function()
  require("logpose.board").refresh(b)
end)
bench("board: move a card (H/L)", function()
  local actions = require("logpose.board.actions")
  b.focus = { col = 1, row = 1 }
  actions.move(b, 1)
end)
bench("board: undo", function()
  require("logpose.board").undo(b)
end)
bench("today", function()
  require("logpose.today").open(root)
end)
for _, view in ipairs({ "notes", "meetings", "people" }) do
  bench(view .. " list", function()
    require("logpose.lists").open(root, require("logpose.lists." .. view), { project = false })
  end)
end
bench("meetings: filter (or, attendees, date)", function()
  require("logpose.lists").open(root, require("logpose.lists.meetings"), {
    project = false,
    filter = "(type:retro or type:planning) date>=2026-01 -project:nothing",
  })
end)
bench("projects: stats", function()
  require("logpose.projects").stats(root)
end)
bench("projects: manager open", function()
  require("logpose.projects").open(root)
end)
bench("standup", function()
  vim.cmd("Logpose standup")
end)
bench("report sprint", function()
  vim.cmd("Logpose report sprint")
end)
bench("actions overdue", function()
  vim.cmd("Logpose actions overdue")
end)
vim.cmd("qa!")

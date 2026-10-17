local out = _G.OUT
vim.o.columns, vim.o.lines = tonumber(_G.COLS or 132), 34
vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.ruler = false
vim.o.cmdheight = 0
vim.cmd.colorscheme(_G.SCHEME or "tokyonight-night")
vim.cmd("runtime plugin/logpose.lua")
require("logpose").setup({
  root = _G.ROOT,
  picker = "select",
  me = "@emmanuel",
  period = { kind = "sprint", sprint = { anchor = "2026-10-15", first_number = 43 } },
})
require("logpose.util.date")._now = function()
  return os.time({ year = 2026, month = 10, day = 15, hour = 10, min = 30 })
end
vim.cmd("cd " .. _G.ROOT)
vim.cmd(_G.CMD or "Logpose board")
vim.wait(300, function()
  return false
end)
local win = vim.api.nvim_get_current_win()
local wb = vim.wo[win].winbar ~= ""
    and vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
  or ""
local f = io.open(out .. ".txt", "w")
f:write(wb, "\n", table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
f:close()
vim.cmd("packadd nvim.tohtml")
local h = io.open(out .. ".html", "w")
h:write(table.concat(require("tohtml").tohtml(win, { title = "logpose" }), "\n"))
h:close()

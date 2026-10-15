-- Minimal init for `make test` and for the child Neovim processes tests spawn.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Keep only Neovim's own runtime (incl. bundled treesitter parsers), never user config/plugins.
local rtp = { root }
for _, p in ipairs(vim.opt.rtp:get()) do
  if vim.startswith(p, vim.env.VIMRUNTIME) or p:find("/lib/nvim", 1, true) then
    table.insert(rtp, p)
  end
end
table.insert(rtp, root .. "/deps/mini.nvim")
vim.opt.rtp = rtp
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.shadafile = "NONE"

vim.cmd("runtime plugin/logpose.lua")
require("mini.test").setup()

if vim.g.loaded_logpose then
  return
end
vim.g.loaded_logpose = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("logpose.nvim requires Neovim 0.10+", vim.log.levels.ERROR)
  return
end

-- Cheap: only the dispatcher loads at startup; feature modules load on use.
require("logpose.commands").create()
require("logpose.tickets").setup_autocmd()
require("logpose.telemetry").setup_autocmd()

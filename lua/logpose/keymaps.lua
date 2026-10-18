--- Opt-in keymaps: `setup({ keymaps = true })` installs a `<leader>j…` set (another prefix with
--- `keymaps = { prefix = "<leader>n" }`). Keys you've already mapped are left alone.
local M = {}

--- suffix, modes, rhs, description
M.MAPS = {
  { "j", "n", "<cmd>Logpose<cr>", "Menu" },
  { "d", "n", "<Plug>(logpose-daily)", "Daily note" },
  { "y", "n", "<cmd>Logpose today<cr>", "Today" },
  { "s", "n", "<Plug>(logpose-standup)", "Standup" },
  { "k", "n", "<Plug>(logpose-board)", "Board" },
  { "w", "n", "<Plug>(logpose-project)", "Switch project" },
  { "P", "n", "<cmd>Logpose projects<cr>", "Projects" },
  { "m", "n", "<Plug>(logpose-meeting)", "Meeting note" },
  { "c", "n", "<Plug>(logpose-capture)", "Capture a task" },
  { "x", { "n", "x" }, "<Plug>(logpose-done)", "Mark done" },
  { "p", "n", "<Plug>(logpose-promote)", "Promote to task file" },
  { "n", "n", "<Plug>(logpose-note)", "Topic note" },
  { "f", "n", "<Plug>(logpose-find)", "Find notes" },
  { "t", "n", "<cmd>Logpose find tasks open<cr>", "Open tasks" },
  { "a", "n", "<Plug>(logpose-actions)", "Action items" },
  { "b", "n", "<Plug>(logpose-backlinks)", "Backlinks" },
  { "r", "n", "<Plug>(logpose-report)", "Report" },
  { "/", "n", "<Plug>(logpose-grep)", "Grep journal" },
}

---@param opts boolean|{ prefix?: string }
---@return string[] installed lhs
function M.apply(opts)
  if not opts then
    return {}
  end
  local prefix = type(opts) == "table" and opts.prefix or "<leader>j"
  local installed = {}
  for _, m in ipairs(M.MAPS) do
    local lhs = prefix .. m[1]
    local modes = type(m[2]) == "table" and m[2] or { m[2] }
    for _, mode in ipairs(modes) do
      if vim.fn.maparg(lhs, mode) == "" then
        vim.keymap.set(mode, lhs, m[3], { desc = m[4], silent = true })
        table.insert(installed, mode .. " " .. lhs)
      end
    end
  end
  local ok, wk = pcall(require, "which-key")
  if ok and type(wk) == "table" and wk.add then
    pcall(wk.add, { { prefix, group = "journal", mode = { "n", "x" } } })
  end
  return installed
end

return M

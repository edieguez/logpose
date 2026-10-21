--- Opt-in keymaps: `setup({ keymaps = true })` installs a `<leader>j…` set (another prefix with
--- `keymaps = { prefix = "<leader>n" }`). Keys you've already mapped are left alone.
local M = {}

--- suffix, modes, rhs, description
M.MAPS = {
  { "j", "n", "<cmd>Logpose<cr>", "Menu" },
  { "y", "n", "<cmd>Logpose today<cr>", "Today" },
  { "s", "n", "<Plug>(logpose-standup)", "Standup" },
  { "r", "n", "<Plug>(logpose-report)", "Report" },
  { "P", "n", "<cmd>Logpose projects<cr>", "Projects" },
  { "e", "n", "<Plug>(logpose-edit)", "Edit details (frontmatter)" },
  { "u", "n", "<Plug>(logpose-people)", "People" },
  -- notes
  { "d", "n", "<Plug>(logpose-daily)", "Note: daily" },
  { "m", "n", "<Plug>(logpose-meeting)", "Note: meeting" },
  { "n", "n", "<Plug>(logpose-note)", "Note: topic" },
  { "l", "n", "<Plug>(logpose-notes)", "Notes: browse" },
  { "M", "n", "<Plug>(logpose-meetings)", "Meetings: browse" },
  { "f", "n", "<Plug>(logpose-find)", "Find notes" },
  { "b", "n", "<Plug>(logpose-backlinks)", "Backlinks" },
  { "/", "n", "<Plug>(logpose-grep)", "Grep journal" },
  -- tasks
  { "k", "n", "<Plug>(logpose-board)", "Tasks: board" },
  { "c", "n", "<Plug>(logpose-capture)", "Task: new" },
  { "X", "n", "<Plug>(logpose-done)", "Task: done" },
  { "t", "n", "<cmd>Logpose find tasks open<cr>", "Tasks: open" },
  -- to-dos (checkboxes in notes)
  { "x", { "n", "x" }, "<Plug>(logpose-check)", "To-do: check off" },
  { "p", "n", "<Plug>(logpose-promote)", "To-do: make it a task" },
  { "o", "n", "<cmd>Logpose find todos open<cr>", "To-dos: open" },
  { "a", "n", "<Plug>(logpose-actions)", "To-dos: meeting action items" },
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

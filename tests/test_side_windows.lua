local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 15)
      H.write(root .. "/people/ana.md", "---\nname: Ana\n---\n")
      H.write(root .. "/tasks/fix-ci.md", '---\ntitle: "Fix CI"\nstatus: todo\n---\n')
    end,
    post_once = child.stop,
  },
})

-- A side window like snacks.nvim's explorer: when another buffer lands in it, it takes its own
-- buffer back and moves the newcomer to the main window (its `fixbuf`).
local function side_window()
  child.lua([[
    vim.cmd("topleft vsplit")
    local side = vim.api.nvim_get_current_win()
    local own = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(side, own)
    vim.w[side].snacks_win = { position = "left" }
    _G.side, _G.own = side, own
    vim.api.nvim_create_autocmd("BufWinEnter", { callback = function()
      if not vim.api.nvim_win_is_valid(side) then return true end
      local buf = vim.api.nvim_win_get_buf(side)
      if buf == own then return end
      local main
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= side then main = w break end
      end
      vim.api.nvim_win_set_buf(side, own)
      vim.api.nvim_win_set_buf(main, buf)
      vim.api.nvim_set_current_win(main)
    end })
  ]])
end

for _, case in ipairs({
  { "people", "logpose-people" },
  { "notes", "logpose-notes" },
  { "projects", "logpose-projects" },
  { "board", "logpose-board" },
}) do
  T[("%s opens beside a plugin's side window"):format(case[1])] = function()
    side_window()
    child.cmd("Logpose " .. case[1])
    eq(child.lua_get("vim.api.nvim_win_get_buf(_G.side) == _G.own"), true)
    eq(child.bo.filetype, case[2])
    eq(child.lua_get("vim.api.nvim_get_current_win() ~= _G.side"), true)
  end
end

T["a screen survives a plugin moving it out of its window"] = function()
  side_window()
  -- the screen is asked for in the side window itself (as from an explorer's key)
  child.lua("vim.w[_G.side].snacks_win = nil; vim.api.nvim_set_current_win(_G.side)")
  child.cmd("Logpose people")
  eq(child.bo.filetype, "logpose-people")
  eq(child.lua_get("vim.api.nvim_win_get_buf(_G.side) == _G.own"), true)
  eq(#child.notifications(), 0)
end

return T

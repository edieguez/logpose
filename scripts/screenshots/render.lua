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
if _G.KEYS and _G.KEYS ~= "" then
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(_G.KEYS, true, false, true), "x", false)
end
--- Record the current window (and any completion menu) as text and HTML.
local function capture()
  local win = vim.api.nvim_get_current_win()
  -- The completion menu, if one is open: where it is (relative to this window) and what it shows.
  if vim.fn.pumvisible() == 1 then
    local pos = vim.fn.pum_getpos()
    local wp = vim.fn.win_screenpos(win)
    local info = vim.fn.complete_info({ "items", "selected" })
    local function color(name)
      local h = vim.api.nvim_get_hl(0, { name = name, link = false })
      return { fg = h.fg and ("#%06x"):format(h.fg), bg = h.bg and ("#%06x"):format(h.bg) }
    end
    local pum = {
      row = pos.row - (wp[1] - 1),
      col = pos.col - (wp[2] - 1),
      selected = info.selected,
      items = vim.tbl_map(function(i)
        return { word = i.word, menu = i.menu or "" }
      end, info.items),
      colors = { menu = color("Pmenu"), sel = color("PmenuSel"), extra = color("PmenuExtra") },
    }
    local pf = io.open(out .. ".pum.json", "w")
    pf:write(vim.json.encode(pum))
    pf:close()
  end
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
end

if _G.TYPE and _G.TYPE ~= "" then
  -- Typed as a user would, so insert mode stays on and completion menus open. Keys typed with
  -- nvim_input only run once we're back in the main loop, so capture (and quit) from a timer.
  _G.ASYNC = true
  vim.api.nvim_input(_G.TYPE)
  vim.defer_fn(function()
    capture()
    vim.cmd("qa!")
  end, 300)
else
  vim.wait(300, function()
    return false
  end)
  capture()
end

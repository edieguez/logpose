--- The filter bar: a one-line input under a list or the board, like Vim's own `/`, so it covers
--- none of what's being filtered. The list updates as you type; a menu offers what can come next
--- (filters, then their values, each with a word on what it does), opening upwards over the
--- bottom of the list; the bar's right end says how many match and which words are ignored. <CR>
--- keeps the filter, <Esc> puts the old one back, <Tab> completes, <F1> shows the cheat sheet.
local M = {}

---@class logpose.FilterBarOpts
---@field win integer        the window it sits over
---@field title string
---@field text string        the filter it starts with
---@field root? string
---@field on_change fun(text: string): string?  apply it live; returns a status ("6 meetings")
---@field on_done fun(text?: string)            nil: cancelled

--- The word being typed before the cursor, and the column (0-based) it starts at.
---@param line string
---@param col integer
---@return string token, integer start
function M.token(line, col)
  local before = line:sub(1, col)
  local token = before:match("[^%s%(%)]*$") or ""
  return token, #before - #token
end

local ns = vim.api.nvim_create_namespace("logpose.filterbar")

--- What each open bar says at its right end (how many match, what's ignored).
---@type table<integer, string>
M.status = {}

---@param opts logpose.FilterBarOpts
---@return integer win
function M.open(opts)
  require("logpose.util.screen").links({ LogposeFilterTitle = "Title", LogposeFilterHint = "Comment" })
  local filter = require("logpose.filter")
  local query = require("logpose.query")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "logpose-filter"
  vim.b[buf].completion = false -- blink.cmp: our own menu
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.text or "" })
  local parent = opts.win
  local win = vim.api.nvim_open_win(buf, true, { split = "below", win = parent, height = 1 })
  vim.wo[win].winfixheight = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].spell = false
  vim.wo[win].foldcolumn = "0"
  -- the prompt, like Vim's `/`: "Filter people › "
  vim.wo[win].statuscolumn = "%#LogposeFilterTitle# " .. opts.title:gsub("%%", "%%%%") .. " › %*"
  vim.wo[win].colorcolumn = ""
  vim.wo[win].list = false
  if package.loaded["cmp"] then
    pcall(function()
      require("cmp").setup.buffer({ enabled = false })
    end)
  end

  local saved_cot, saved_ph = vim.o.completeopt, vim.o.pumheight
  vim.o.completeopt = "menuone,noinsert,noselect"
  vim.o.pumheight = 10 -- the menu leaves most of the list in view
  local done = false
  local pending

  local function text()
    return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  end
  local function status(msg)
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    local _, skipped = query.parse(query.split(text()), nil, true)
    local parts = {}
    if msg and msg ~= "" then
      table.insert(parts, msg)
    end
    if #skipped > 0 then
      table.insert(parts, "ignored: " .. table.concat(skipped, " "))
    end
    if text() == "" then
      table.insert(parts, "try type:retro or @ana · date>=-7d · -#draft")
    end
    table.insert(parts, "Tab complete · F1 help")
    M.status[win] = table.concat(parts, " · ")
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = { { M.status[win] .. " ", "LogposeFilterHint" } },
      virt_text_pos = "right_align",
    })
  end
  local function apply()
    pending = nil
    local ok, msg = pcall(opts.on_change, text())
    status(ok and msg or nil)
  end
  local function schedule_apply()
    if pending then
      return
    end
    pending = true
    vim.defer_fn(function()
      if not done then
        apply()
      end
    end, 40)
  end
  local dismissed -- the line when the menu was closed: not offered again until it changes
  local function popup(force)
    if vim.fn.mode() ~= "i" or (not force and dismissed == text()) then
      return
    end
    dismissed = nil
    local col = vim.api.nvim_win_get_cursor(win)[2]
    local token, start = M.token(text(), col)
    -- between words the menu stays shut (Tab opens it), so what matched stays in view
    local items = (force or token ~= "") and filter.complete(token, opts.root) or {}
    if #items == 0 or (#items == 1 and items[1].word == token) then
      if vim.fn.pumvisible() == 1 then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
      end
      return
    end
    vim.fn.complete(start + 1, items)
  end
  local function finish(value)
    if done then
      return
    end
    done = true
    vim.o.completeopt, vim.o.pumheight = saved_cot, saved_ph
    M.status[win] = nil
    vim.cmd("stopinsert")
    pcall(vim.api.nvim_win_close, win, true)
    if vim.api.nvim_win_is_valid(parent) then
      vim.api.nvim_set_current_win(parent)
    end
    opts.on_done(value)
  end

  local group = vim.api.nvim_create_augroup("logpose.filterbar." .. buf, { clear = true })
  local seen = opts.text or ""
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = buf,
    callback = function()
      if text() == seen then
        return -- entering Insert mode fires this too: nothing was typed
      end
      seen = text()
      schedule_apply()
      popup()
    end,
  })
  vim.api.nvim_create_autocmd("TextChanged", { group = group, buffer = buf, callback = schedule_apply })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      -- clicking elsewhere keeps what's typed (the help window comes back here)
      vim.schedule(function()
        local cur = vim.api.nvim_get_current_win()
        if not done and cur ~= win and vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= "logpose-help" then
          finish(text())
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      vim.o.completeopt, vim.o.pumheight = saved_cot, saved_ph
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  local function map(modes, lhs, rhs, expr)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true, silent = true, expr = expr })
  end
  map({ "i", "n" }, "<CR>", function()
    if vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected ~= -1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
      return
    end
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
    end
    finish(vim.trim(text()))
  end)
  map("i", "<Esc>", function()
    if vim.fn.pumvisible() == 1 then
      dismissed = text()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
      return
    end
    finish(nil)
  end)
  map("n", "<Esc>", function()
    finish(nil)
  end)
  map("n", "q", function()
    finish(nil)
  end)
  map("i", "<Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    return "<Cmd>lua require('logpose.filter.bar')._popup(true)<CR>"
  end, true)
  map("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or ""
  end, true)
  map({ "i", "n" }, "<F1>", function()
    require("logpose.util.help").open("Filters", filter.cheatsheet_lines())
  end)
  M._popup = popup

  if (opts.text or "") == "" then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        vim.schedule(function()
          popup(true) -- an empty bar: show what can be typed
        end)
      end,
    })
  end
  vim.cmd("startinsert!")
  apply() -- the count to start with
  return win
end

return M

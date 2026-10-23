--- What logpose's screens (the board, the lists, today, projects, help windows) share: drawing
--- lines of highlighted chunks into a locked buffer, default highlight links, and leaving.
local M = {}

---@alias logpose.Chunk { [1]: string, [2]?: string }

--- Replace `buf`'s text with `lines` (each a list of chunks: text and a highlight group), locked
--- and unmodified; trailing spaces are dropped and highlights clipped to the text.
---@param buf integer
---@param ns integer
---@param lines logpose.Chunk[][]
---@return string[] texts
function M.draw(buf, ns, lines)
  local texts = {}
  for i, chunks in ipairs(lines) do
    local parts = {}
    for _, c in ipairs(chunks) do
      table.insert(parts, c[1])
    end
    texts[i] = (table.concat(parts):gsub("%s+$", ""))
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, chunks in ipairs(lines) do
    local col = 0
    for _, c in ipairs(chunks) do
      local end_col = math.min(col + #c[1], #texts[i])
      if c[2] and end_col > col then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = end_col, hl_group = c[2] })
      end
      col = col + #c[1]
    end
  end
  return texts
end

--- Link highlight groups to defaults (yours win: `default = true`).
---@param links table<string, string>
function M.links(links)
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

--- Leave a screen: its window shows the buffer you were in before (or an empty one).
---@param buf integer the screen's buffer
---@param win? integer default: the current window
function M.leave(buf, win)
  local function go()
    local alt = vim.fn.bufnr("#")
    if alt > 0 and alt ~= buf and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
      vim.cmd.buffer(alt)
    else
      vim.cmd.enew()
    end
  end
  if win and win ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_win_call(win, go)
  else
    go()
  end
end

return M

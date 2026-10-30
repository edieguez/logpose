--- What logpose's screens (the board, the lists, today, projects, help windows) share: drawing
--- lines of highlighted chunks into a locked buffer, default highlight links, and leaving.
local M = {}

---@alias logpose.Chunk { [1]: string, [2]?: string }

--- Replace `buf`'s text with `lines` (each a list of chunks: text and a highlight group), locked
--- and unmodified; trailing spaces are dropped and highlights clipped to the text. A line with a
--- `band = { hl, from, width }` field gets a background from byte `from` to display column
--- `width` (padded past the text with virtual spaces, so the buffer's text stays the same).
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
    local band = chunks.band
    if band then
      local from = math.min(band.from or 0, #texts[i])
      local pad = band.width - vim.fn.strdisplaywidth(texts[i])
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, from, {
        end_col = #texts[i],
        hl_group = band.hl,
        priority = 50,
      })
      if pad > 0 then
        -- past the end of the text: spaces that aren't in the buffer
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, #texts[i], {
          virt_text = { { string.rep(" ", pad), band.hl } },
          virt_text_pos = "inline",
        })
      end
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

--- A background a little off the editor's for banded rows (`LogposeBand`, yours if you set it).
--- Worked out from `Normal` (5% towards the text colour); `CursorColumn` without colours.
function M.band_hl()
  local name = "LogposeBand"
  local cur = vim.api.nvim_get_hl(0, { name = name })
  if next(cur) and not vim.deep_equal(cur, M._band) then
    return name -- set by you or your colour scheme
  end
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg, fg = normal.bg, normal.fg
  if not bg then
    vim.api.nvim_set_hl(0, name, { link = "CursorColumn" })
  else
    fg = fg or (vim.o.background == "light" and 0x000000 or 0xffffff)
    local function mix(shift)
      local x, y = math.floor(bg / shift) % 256, math.floor(fg / shift) % 256
      return math.floor(x + (y - x) * 0.05 + 0.5) * shift
    end
    vim.api.nvim_set_hl(0, name, { bg = mix(0x10000) + mix(0x100) + mix(1) })
  end
  M._band = vim.api.nvim_get_hl(0, { name = name })
  return name
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("logpose.screen.band", { clear = true }),
  callback = function()
    if M._band then
      M.band_hl() -- ours: work it out again for the new colours
    end
  end,
})

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

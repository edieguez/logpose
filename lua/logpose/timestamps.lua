--- `created:` and `modified:` in note frontmatter, as local ISO 8601 date-times (2026-10-15T18:57).
--- `modified:` is bumped whenever logpose rewrites a note and when you save one in Neovim
--- (only notes that already have the key, so older notes are left alone).
local M = {}

M.FORMAT = "%Y-%m-%dT%H:%M"

---@return string
function M.now()
  return os.date(M.FORMAT, require("logpose.util.date")._now()) --[[@as string]]
end

--- Frontmatter lines for a new note, per `timestamps` config.
---@return string[]
function M.lines()
  local cfg = require("logpose.config").get().timestamps
  local now, out = M.now(), {}
  if cfg.created then
    table.insert(out, "created: " .. now)
  end
  if cfg.modified then
    table.insert(out, "modified: " .. now)
  end
  return out
end

--- Set an existing `modified:` key in the frontmatter of `lines` to now.
---@param lines string[]
---@return string[] lines, boolean changed
function M.touch(lines)
  if lines[1] ~= "---" or not require("logpose.config").get().timestamps.modified then
    return lines, false
  end
  for i = 2, math.min(#lines, 100) do
    if lines[i] == "---" then
      return lines, false
    end
    if lines[i]:match("^modified:") then
      local new = "modified: " .. M.now()
      if lines[i] == new then
        return lines, false
      end
      lines[i] = new
      return lines, true
    end
  end
  return lines, false
end

--- `M.touch` for a whole text.
---@param text string
---@return string
function M.touch_text(text)
  if text:sub(1, 4) ~= "---\n" then
    return text
  end
  local lines = vim.split(text, "\n", { plain = true })
  local changed
  lines, changed = M.touch(lines)
  return changed and table.concat(lines, "\n") or text
end

--- Before saving a changed journal note: bump its `modified:`.
---@param buf integer
function M.on_write(buf)
  if not vim.bo[buf].modified then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local root = require("logpose.config").resolve_root(buf)
  if not root or path == "" or not require("logpose.util.fs").inside(path, root) then
    return
  end
  local head = vim.api.nvim_buf_get_lines(buf, 0, 100, false)
  local lines, changed = M.touch(vim.deepcopy(head))
  if not changed then
    return
  end
  for i, line in ipairs(lines) do
    if line ~= head[i] then
      pcall(vim.cmd.undojoin) -- part of the edit being saved, not a separate undo step
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { line })
      return
    end
  end
end

function M.setup_autocmd()
  local group = vim.api.nvim_create_augroup("logpose.timestamps", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      pcall(M.on_write, ev.buf)
    end,
  })
  -- A note saved from Neovim: the index's results for this moment are out of date.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = function()
      local index = package.loaded["logpose.index"]
      if type(index) == "table" then
        index.clear_cache()
      end
    end,
  })
end

return M

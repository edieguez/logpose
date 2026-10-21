--- Ticket references: `gx` on PROJ-123 opens the tracker (`tickets.url`), `:Logpose ticket [ID]`
--- lists every journal line that mentions it. `gx` in a journal note also follows note links
--- (`[[meetings/acme/2026-10-14 - retro|Retro]]`, which have spaces `<cfile>` stops at).
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

--- Ticket ID at byte column `col` (0-based) of `line`, if any.
---@param line string
---@param col integer
---@return string?
function M.at(line, col)
  local pattern = config.get().tickets.pattern
  local init = 1
  while true do
    local s, e = line:find(pattern, init)
    if not s then
      return nil
    end
    -- Whole word only: not preceded/followed by a letter or digit.
    local before, after = line:sub(s - 1, s - 1), line:sub(e + 1, e + 1)
    local whole = not before:match("[%w]") and not after:match("[%w]")
    if whole and col + 1 >= s and col + 1 <= e then
      return line:sub(s, e)
    end
    init = e + 1
  end
end

---@param id string
---@return string?
function M.url(id)
  local tpl = config.get().tickets.url
  return tpl and require("logpose.util.text").substitute(tpl, { id = id }) or nil
end

--- Every line in the journal mentioning `id`.
---@param root string
---@param id string
---@return logpose.PickItem[]
function M.mentions(root, id)
  local out = {}
  local pat = "%f[%w]" .. vim.pesc(id) .. "%f[^%w]"
  for _, path in ipairs(require("logpose.index").files(root)) do
    for lnum, line in ipairs(fs.read_lines(path) or {}) do
      if line:find(pat) then
        table.insert(out, {
          display = ("%s: %s"):format(require("logpose.link").relpath(root, path), vim.trim(line)),
          file = path,
          lnum = lnum,
        })
      end
    end
  end
  return out
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local id = opts.args[1]
  if not id then
    local col = vim.api.nvim_win_get_cursor(0)[2]
    id = M.at(vim.api.nvim_get_current_line(), col)
    if not id then
      error("logpose: no ticket under the cursor; use :Logpose ticket ID", 0)
    end
  end
  config.with_root(ui.safely(function(root)
    local found = M.mentions(root, id)
    if #found == 0 then
      require("logpose.util.ui").notify(("logpose: %s isn't mentioned anywhere"):format(id), vim.log.levels.INFO)
      return
    end
    require("logpose.picker").pick(found, { prompt = id, cwd = root })
  end))
end

--- What `gx` did in each buffer before logpose mapped it (your markdown plugin's, or Neovim's).
---@type table<integer, table>
local previous = {}

--- `gx`: the ticket under the cursor opens in the tracker, a link to a note opens the note;
--- anything else goes to the `gx` you had (a URL opens in the browser).
function M.gx()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local id = M.at(line, col)
  local url = id and M.url(id)
  if url then
    vim.ui.open(url)
    return
  end
  local root = config.resolve_root()
  if root then
    local path, link = require("logpose.links").follow(root, fs.normalize(vim.api.nvim_buf_get_name(buf)), line, col)
    if path then
      vim.cmd.edit(vim.fn.fnameescape(path))
      return
    elseif link and link.style == "wiki" then
      ui.notify(("logpose: no note at [[%s]]"):format(link.target), vim.log.levels.WARN)
      return
    end
  end
  local prev = previous[buf]
  if prev and prev.callback then
    prev.callback()
  elseif prev and prev.rhs and prev.rhs ~= "" then
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(prev.rhs, true, false, true),
      prev.noremap == 1 and "n" or "m",
      false
    )
  else
    vim.ui.open(vim.fn.expand("<cfile>"))
  end
end

--- Buffer-local setup for markdown buffers inside the journal: `gx` (tickets and note links).
---@param buf integer
function M.attach(buf)
  local root = config.resolve_root()
  local name = vim.api.nvim_buf_get_name(buf)
  if not root or name == "" then
    return
  end
  local abs = fs.normalize(name)
  if not vim.startswith(abs, fs.normalize(root) .. "/") then
    return
  end
  local prev = vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg("gx", "n", false, true)
  end)
  if prev.desc ~= "logpose: follow a link or open a ticket" then
    previous[buf] = next(prev) and prev or nil
  end
  vim.keymap.set("n", "gx", M.gx, { buffer = buf, desc = "logpose: follow a link or open a ticket" })
end

function M.setup_autocmd()
  vim.api.nvim_set_hl(0, "LogposeTicket", { link = "Underlined", default = true })
  local group = vim.api.nvim_create_augroup("logpose_tickets", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      pcall(M.attach, ev.buf)
    end,
  })
end

return M

--- Ticket references: `gx` on PROJ-123 opens the tracker (`tickets.url`), `:Logpose ticket [ID]`
--- lists every journal line that mentions it.
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
      vim.notify(("logpose: %s isn't mentioned anywhere"):format(id), vim.log.levels.INFO)
      return
    end
    require("logpose.picker").pick(found, { prompt = id, cwd = root })
  end))
end

--- `gx`: open the ticket under the cursor, else behave like the default `gx`.
function M.gx()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local id = M.at(vim.api.nvim_get_current_line(), col)
  local url = id and M.url(id)
  if url then
    vim.ui.open(url)
    return
  end
  vim.ui.open(vim.fn.expand("<cfile>"))
end

--- Buffer-local setup for markdown buffers inside the journal: `gx` and highlighting.
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
  if config.get().tickets.url then
    vim.keymap.set("n", "gx", M.gx, { buffer = buf, desc = "logpose: open ticket or link" })
  end
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

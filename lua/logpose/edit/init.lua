--- `:Logpose edit`: a floating form for a note's frontmatter (or several tasks' at once), with
--- completion, a check of each value as you type and a preview of what saving does. See
--- `edit.fields` (the model), `edit.form` (the window) and `edit.save` (applying changes).
local config = require("logpose.config")
local fields = require("logpose.edit.fields")
local form = require("logpose.edit.form")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

M.FIELDS = fields.FIELDS
M.MANAGED = fields.MANAGED
M.candidates = form.candidates
M.omnifunc = form.omnifunc

--- Open the editor for one note. `opts.on_save(new_path, keys)` runs after a save.
---@param path string
---@param opts? { root?: string, on_save?: fun(path: string, keys: string[]) }
---@return integer win
function M.open(path, opts)
  opts = opts or {}
  local root = opts.root or config.root()
  return form.show(fields.load(fs.normalize(path), root), { on_save = opts.on_save })
end

--- Open the editor for several task files at once. `opts.on_save(paths, keys)` runs after.
---@param paths string[]
---@param opts? { root?: string, on_save?: fun(paths: string[], keys: string[]) }
---@return integer win
function M.open_bulk(paths, opts)
  opts = opts or {}
  local root = opts.root or config.root()
  paths = vim.tbl_map(fs.normalize, paths)
  return form.show(fields.load_bulk(paths, root), { on_save = opts.on_save })
end

--- Task files among the quickfix (or location list) entries on rows `line1`..`line2` of the
--- list window in the current window.
---@param root string
---@param line1 integer
---@param line2 integer
---@return string[]
local function list_tasks(root, line1, line2)
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1] or {}
  local items = info.loclist == 1 and vim.fn.getloclist(0) or vim.fn.getqflist()
  local taskfile = require("logpose.taskfile")
  local out, seen = {}, {}
  for i = line1, line2 do
    local it = items[i]
    local name = it and it.bufnr and it.bufnr > 0 and vim.api.nvim_buf_get_name(it.bufnr) or ""
    if name ~= "" then
      local p = fs.normalize(name)
      if not seen[p] and taskfile.is_task_file(p, root) then
        seen[p] = true
        table.insert(out, p)
      end
    end
  end
  return out
end

--- `:Logpose edit [last]`: the current note, the task captured last (also when the current
--- buffer isn't a journal note, so the key right after a capture fixes it), or the tasks on
--- the selected lines of a quickfix list.
---@param opts logpose.CommandOpts
function M.command(opts)
  local last = require("logpose.tasks").last
  local want_last = opts.args[1] == "last"
  config.with_root(ui.safely(function(root)
    if vim.bo.buftype == "quickfix" and not want_last then
      local l1, l2 = vim.fn.line("."), vim.fn.line(".")
      if opts.range and opts.range > 0 then
        l1, l2 = opts.line1, opts.line2
      end
      local paths = list_tasks(root, l1, l2)
      if #paths == 0 then
        error("logpose: no task files on these lines", 0)
      elseif #paths == 1 then
        M.open(paths[1], { root = root })
      else
        M.open_bulk(paths, { root = root })
      end
      return
    end
    local path = vim.api.nvim_buf_get_name(0)
    local p = path ~= "" and fs.normalize(path) or ""
    local in_journal = vim.bo.buftype == "" and p:match("%.md$") ~= nil and vim.startswith(p, fs.normalize(root) .. "/")
    if want_last or not in_journal then
      if last and fs.exists(last) then
        M.open(last, { root = root })
        return
      end
      if want_last then
        error("logpose: nothing captured yet in this session", 0)
      end
      error("logpose: :Logpose edit works on a journal note (on the board, press e)", 0)
    end
    M.open(p, { root = root })
  end))
end

---@param arglead string
function M.complete(arglead, _)
  return vim.startswith("last", arglead) and { "last" } or {}
end

return M

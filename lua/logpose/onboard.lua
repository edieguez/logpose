--- Onboarding: `:Logpose init [dir]` and the first-run prompt.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local state = require("logpose.state")
local ui = require("logpose.util.ui")

local M = {}

M.DEFAULT_DIR = "~/journal"

--- Make `dir` the journal: create it if needed, add the root marker, scaffold an
--- empty directory, and save it as the default root.
---@param dir string
---@return string root, boolean scaffolded
function M.init(dir)
  local root = fs.normalize(dir):gsub("/+$", "")
  if root == "" then
    root = "/"
  end
  if fs.exists(root) and not fs.is_dir(root) then
    error(("logpose: %s is a file, not a directory"):format(dir), 0)
  end
  local empty = not fs.is_dir(root) or #vim.fn.readdir(root) == 0
  fs.mkdir_p(root)

  local function write(path, content)
    local ok, err = fs.write_file(path, content)
    if not ok then
      error(err, 0)
    end
  end

  local marker = config.get().root_markers[1]
  if marker and marker ~= ".git" and not fs.exists(fs.join(root, marker)) then
    write(fs.join(root, marker), "")
  end

  if empty then
    fs.mkdir_p(config.path("daily", root))
    fs.mkdir_p(config.path("meetings", root))
    for _, item in ipairs({ { "inbox", "# INBOX\n" }, { "done", "# DONE\n" } }) do
      local path = config.path(item[1], root)
      if not fs.exists(path) then
        write(path, item[2])
      end
    end
  end

  state.set("root", root)
  return root, empty
end

--- Initialise `dir`, report it, then continue with `on_done(root)`.
---@param dir string
---@param on_done? fun(root: string)
function M.run(dir, on_done)
  local root, scaffolded = M.init(dir)
  local short = vim.fn.fnamemodify(root, ":~")
  if scaffolded then
    vim.notify(("logpose: created a journal at %s"):format(short), vim.log.levels.INFO)
  else
    vim.notify(("logpose: using %s as the journal"):format(short), vim.log.levels.INFO)
  end
  local configured = config.get().root
  if configured and fs.normalize(configured):gsub("/+$", "") ~= root then
    vim.notify(
      ("logpose: setup({ root = %q }) takes precedence over the saved journal"):format(configured),
      vim.log.levels.WARN
    )
  end
  if on_done then
    on_done(root)
  end
end

--- Ask for the journal directory, then `run` it.
---@param opts? { first_run?: boolean }
---@param on_done? fun(root: string)
function M.prompt(opts, on_done)
  opts = opts or {}
  local saved = state.get("root")
  local default = type(saved) == "string" and vim.fn.fnamemodify(saved, ":~") or M.DEFAULT_DIR
  vim.ui.input(
    {
      prompt = opts.first_run and "No journal found. Create one at: " or "Journal directory: ",
      default = default,
      completion = "dir",
    },
    ui.safely(function(input)
      input = input and vim.trim(input) or ""
      if input == "" then
        if opts.first_run then
          vim.notify(config.NOT_FOUND, vim.log.levels.WARN)
        else
          vim.notify("logpose: cancelled", vim.log.levels.INFO)
        end
        return
      end
      M.run(input, on_done)
    end)
  )
end

---@param opts logpose.CommandOpts
function M.command(opts)
  if #opts.args > 0 then
    M.run(table.concat(opts.args, " "))
  else
    M.prompt()
  end
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  return vim.fn.getcompletion(arglead, "dir")
end

return M

--- Projects: one journal, notes tagged by the project you're working on.
--- `:Logpose project [name|none]`.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local state = require("logpose.state")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

---@alias logpose.ProjectSource "explicit"|"path"|"git"

--- Project names are used in paths, so they are always slugs.
---@param name string
---@return string? slug
function M.normalize(name)
  local slug = text.slugify(name or "")
  return slug ~= "" and slug or nil
end

--- The file or directory used to detect the project: the current buffer if it's a real
--- file, otherwise the cwd.
---@return string
local function context_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" and not name:match("^%a[%w+.-]*://") then
    return fs.normalize(name)
  end
  return fs.normalize(vim.fn.getcwd())
end

---@param path string
---@param dir string
---@return boolean
local function is_within(path, dir)
  dir = dir:gsub("/+$", "")
  return path == dir or vim.startswith(path, dir .. "/")
end

--- Active project: set explicitly -> `projects.paths` -> git repo -> none.
--- Detection never applies inside the journal itself.
---@param root? string journal root
---@return string? name, logpose.ProjectSource? source
function M.resolve(root)
  local explicit = state.get("project")
  if type(explicit) == "string" and explicit ~= "" then
    return explicit, "explicit"
  end

  local ctx = context_path()
  if root and is_within(ctx, fs.normalize(root)) then
    return nil
  end

  local opts = config.get().projects
  local best, best_len
  for dir, name in pairs(opts.paths) do
    local d = fs.normalize(dir):gsub("/+$", "")
    if is_within(ctx, d) and (not best_len or #d > best_len) then
      best, best_len = name, #d
    end
  end
  if best then
    return M.normalize(best), "path"
  end

  if opts.detect then
    local repo = vim.fs.root(ctx, ".git")
    if repo then
      return M.normalize(vim.fs.basename(repo)), "git"
    end
  end
  return nil
end

--- Active project for the current context (nil if none or no journal).
---@return string?
function M.current()
  local root = config.resolve_root()
  return (M.resolve(root))
end

--- Projects known so far: explicit, configured, and subdirectories of the meetings dir.
---@param root? string
---@return string[]
function M.known(root)
  local seen, out = {}, {}
  local function add(name)
    name = name and M.normalize(name)
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  add(state.get("project"))
  for _, name in pairs(config.get().projects.paths) do
    add(name)
  end
  if root and config.get().meeting_subdir:find("{project}", 1, true) then
    local dir = config.path("meetings", root)
    if fs.is_dir(dir) then
      for entry, kind in vim.fs.dir(dir) do
        if kind == "directory" then
          add(entry)
        end
      end
    end
  end
  table.sort(out)
  return out
end

local SOURCE_LABEL = {
  explicit = "set with :Logpose project",
  path = "from projects.paths",
  git = "from the git repo",
}

---@param name? string
---@param source? string
---@return string
function M.describe(name, source)
  if not name then
    return "no active project"
  end
  return ("project %s (%s)"):format(name, SOURCE_LABEL[source] or source)
end

--- Set (or clear with nil) the explicit project.
---@param name? string
function M.set(name)
  if name == nil then
    state.set("project", nil)
    local root = config.resolve_root()
    vim.notify("logpose: project cleared; now " .. M.describe(M.resolve(root)), vim.log.levels.INFO)
    return
  end
  local slug = M.normalize(name)
  if not slug then
    error(("logpose: invalid project name %q"):format(name), 0)
  end
  state.set("project", slug)
  vim.notify("logpose: project set to " .. slug, vim.log.levels.INFO)
end

local CLEAR = { "none", "auto", "clear" }

---@param opts logpose.CommandOpts
function M.command(opts)
  local arg = table.concat(opts.args, " ")
  if arg ~= "" then
    if vim.tbl_contains(CLEAR, arg) then
      M.set(nil)
    else
      M.set(arg)
    end
    return
  end

  local root = config.resolve_root()
  local current, source = M.resolve(root)
  local items = {}
  for _, name in ipairs(M.known(root)) do
    table.insert(items, { label = name, value = name })
  end
  table.insert(items, { label = "New project…", new = true })
  table.insert(items, { label = "Auto-detect (clear)", clear = true })
  vim.ui.select(
    items,
    {
      prompt = "Project (now: " .. M.describe(current, source) .. ")",
      format_item = function(item)
        return item.label
      end,
    },
    ui.safely(function(choice)
      if not choice then
        return
      end
      if choice.clear then
        M.set(nil)
      elseif choice.new then
        vim.ui.input(
          { prompt = "Project name: " },
          ui.safely(function(input)
            if input and vim.trim(input) ~= "" then
              M.set(input)
            end
          end)
        )
      else
        M.set(choice.value)
      end
    end)
  )
end

---@return string[]
function M.complete(_, args)
  if #args > 0 then
    return {}
  end
  local items = M.known(config.resolve_root())
  table.insert(items, "none")
  return items
end

return M

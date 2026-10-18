--- Projects: one journal, notes tagged by the project you're working on.
--- `:Logpose project [name|none]`.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local state = require("logpose.state")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

---@alias logpose.ProjectSource "explicit"|"path"|"page"|"git"

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

--- Active project: set explicitly -> `projects.paths` -> a project page's `paths:` -> git repo
--- -> none.
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

  if root then
    for name, page in pairs(M.pages(root)) do
      for _, dir in ipairs(page.paths) do
        local d = fs.normalize(dir):gsub("/+$", "")
        if is_within(ctx, d) and (not best_len or #d > best_len) then
          best, best_len = name, #d
        end
      end
    end
    if best then
      return best, "page"
    end
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

---@class logpose.ProjectPage
---@field path string
---@field archived boolean
---@field title? string        display name ("Acme API")
---@field description? string  one line about the project
---@field paths string[]       folders (repos) that belong to the project, for detection
---@field color? string        "#7aa2f7" or a highlight group, for its cards on the board
---@field merged_into? string

--- Project pages: `projects/<name>.md`, keyed by project. A page is what makes a project exist
--- before it has any notes or tasks, and holds what logpose knows about it: its display name,
--- description, repo folders, colour, and whether it's archived.
---@param root string
---@return table<string, logpose.ProjectPage>
function M.pages(root)
  local out = {}
  local dir = config.path("projects", root)
  if not fs.is_dir(dir) then
    return out
  end
  local index = require("logpose.index")
  for entry, kind in vim.fs.dir(dir) do
    if kind == "file" and entry:match("%.md$") then
      local path = fs.join(dir, entry)
      local fm = index.frontmatter(fs.read_lines(path) or {})
      local name = M.normalize(type(fm.project) == "string" and fm.project or entry:gsub("%.md$", ""))
      if name then
        local function str(v)
          return type(v) == "string" and v ~= "" and v or nil
        end
        local paths = fm.paths
        if type(paths) == "string" then
          paths = paths ~= "" and { paths } or {}
        end
        out[name] = {
          path = path,
          archived = fm.archived == "true" or fm.archived == "yes",
          title = str(fm.title),
          description = str(fm.description),
          paths = paths or {},
          color = str(fm.color),
          merged_into = str(fm.merged_into),
        }
      end
    end
  end
  return out
end

--- Archived projects (from their pages).
---@param root? string
---@return table<string, boolean>
function M.archived(root)
  local out = {}
  if not root then
    return out
  end
  for name, page in pairs(M.pages(root)) do
    if page.archived then
      out[name] = true
    end
  end
  return out
end

--- Every project the journal knows about: the pinned one, `projects.paths`, project pages,
--- meeting folders, and the `project:` of any note or task. Archived projects are left out
--- unless `opts.archived`.
---@param root? string
---@param opts? { archived?: boolean }
---@return string[]
function M.known(root, opts)
  local seen, out = {}, {}
  local archived = (opts and opts.archived) and {} or M.archived(root)
  local function add(name)
    name = name and M.normalize(name)
    if name and not seen[name] and not archived[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  add(state.get("project"))
  for _, name in pairs(config.get().projects.paths) do
    add(name)
  end
  if root then
    for name in pairs(M.pages(root)) do
      add(name)
    end
    if config.get().meeting_subdir:find("{project}", 1, true) then
      local dir = config.path("meetings", root)
      if fs.is_dir(dir) then
        for entry, kind in vim.fs.dir(dir) do
          if kind == "directory" then
            add(entry)
          end
        end
      end
    end
    for _, item in ipairs(require("logpose.index").build(root)) do
      add(item.project)
    end
  end
  table.sort(out)
  return out
end

--- Display name of a project: its page title, else the project name.
---@param root? string
---@param name string
---@return string
function M.title(root, name)
  local page = root and M.pages(root)[name]
  return page and page.title or name
end

--- Set (or remove, with nil) a frontmatter key in a project's page, creating the page if it has
--- none.
---@param root string
---@param name string
---@param key string
---@param value? string already formatted as YAML
---@return string path
function M.set_page_field(root, name, key, value)
  local slug = M.normalize(name)
  if not slug then
    error(("logpose: invalid project name %q"):format(name), 0)
  end
  local page = M.pages(root)[slug]
  local path = page and page.path or require("logpose.notes.topic").project_page(root, slug, { open = false })
  local ok, err = fs.update_lines(path, function(lines)
    local close
    for i = 2, #lines do
      if lines[i] == "---" then
        close = i
        break
      end
    end
    if lines[1] ~= "---" or not close then
      return nil
    end
    local at = close
    for i = 2, close - 1 do
      if lines[i]:match("^" .. vim.pesc(key) .. ":") then
        table.remove(lines, i)
        close, at = close - 1, i
        break
      end
    end
    if value ~= nil then
      table.insert(lines, at, key .. ": " .. value)
    end
    return lines
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  return path
end

--- Archive (or restore) a project: `archived: true` in its page, created if it has none. Its
--- notes and tasks stay where they are and stay searchable; it just drops out of completion,
--- the project picker and the all-projects board. Archiving the pinned project unpins it.
---@param root string
---@param name string
---@param archived boolean
function M.set_archived(root, name, archived)
  local slug = M.normalize(name)
  M.set_page_field(root, name, "archived", archived and "true" or nil)
  if archived and state.get("project") == slug then
    state.set("project", nil)
  end
  M.changed()
end

--- Create a project: its page, with a display name and the folders that belong to it.
---@param root string
---@param title string as typed ("Acme API")
---@param paths? string[] repo folders (`~` kept as typed)
---@return string slug
function M.add(root, title, paths)
  local slug = M.normalize(title)
  if not slug then
    error(("logpose: invalid project name %q"):format(title), 0)
  end
  require("logpose.notes.topic").project_page(root, title, { open = false })
  if paths and #paths > 0 then
    M.set_page_field(root, slug, "paths", "[" .. table.concat(paths, ", ") .. "]")
  end
  M.changed()
  return slug
end

--- Projects you switched to, most recent first.
---@return string[]
function M.recent()
  local list = state.get("recent_projects")
  return type(list) == "table" and list or {}
end

---@param name string
local function remember(name)
  local list = { name }
  for _, p in ipairs(M.recent()) do
    if p ~= name and #list < 20 then
      table.insert(list, p)
    end
  end
  state.set("recent_projects", list)
end

--- Highlight group for a project's colour (nil when its page sets none).
---@param root string
---@param name string
---@param pages? table<string, logpose.ProjectPage>
---@return string?
function M.hl(root, name, pages)
  local page = (pages or M.pages(root))[name]
  local color = page and page.color
  if not color then
    return nil
  end
  local group = "LogposeProject_" .. name:gsub("[^%w]", "_")
  if color:match("^#%x%x%x%x%x%x$") then
    vim.api.nvim_set_hl(0, group, { fg = color, default = false })
  else
    vim.api.nvim_set_hl(0, group, { link = color, default = false })
  end
  return group
end

--- Tell open boards, the statusline and anyone listening (`User LogposeProjectChanged`) that the
--- active project or the list of projects changed.
function M.changed()
  pcall(function()
    require("logpose.statusline").clear()
  end)
  vim.api.nvim_exec_autocmds("User", { pattern = "LogposeProjectChanged", modeline = false })
end

local SOURCE_LABEL = {
  explicit = "set with :Logpose project",
  path = "from projects.paths",
  page = "from its project page",
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
    M.changed()
    local root = config.resolve_root()
    require("logpose.util.ui").notify(
      "logpose: project cleared; now " .. M.describe(M.resolve(root)),
      vim.log.levels.INFO
    )
    return
  end
  local slug = M.normalize(name)
  if not slug then
    error(("logpose: invalid project name %q"):format(name), 0)
  end
  state.set("project", slug)
  remember(slug)
  M.changed()
  require("logpose.util.ui").notify("logpose: project set to " .. slug, vim.log.levels.INFO)
end

--- Switch to project `name` (as `set`), then open its board, unless `projects.open_board` is
--- off or you're already on the board (which follows the switch by itself).
---@param name string
function M.switch_to(name)
  M.set(name)
  if not config.get().projects.open_board or vim.bo.filetype == "logpose-board" then
    return
  end
  local root = config.resolve_root()
  if root then
    require("logpose.board").open_board(root)
  end
end

local CLEAR = { "none", "auto", "clear" }

---@param opts logpose.CommandOpts
function M.command(opts)
  local arg = table.concat(opts.args, " ")
  if arg ~= "" then
    if vim.tbl_contains(CLEAR, arg) then
      M.set(nil)
    else
      M.switch_to(arg)
    end
    return
  end

  config.with_root(ui.safely(function(root)
    require("logpose.projects").switch(root)
  end))
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

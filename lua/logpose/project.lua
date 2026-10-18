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
    if not require("logpose.frontmatter").close(lines) then
      return nil
    end
    local v = value
    if v == nil then
      v = false -- removed
    end
    return require("logpose.frontmatter").set(lines, { [key] = v })
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
  M.set_page_field(root, name, "archived", archived or nil)
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
    M.set_page_field(root, slug, "paths", paths)
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

-- Colours for projects without a `color:`: the colour scheme's own hues, taken from groups
-- every scheme defines, without those the board gives a meaning to (errors and overdue in red,
-- due soon and idle in yellow, marked cards in green) and without plain text and comments.
local PALETTE_GROUPS = {
  "Function",
  "String",
  "Type",
  "Constant",
  "Keyword",
  "Special",
  "Statement",
  "PreProc",
  "DiagnosticInfo",
  "DiagnosticHint",
  "Number",
  "Character",
  "Identifier",
}
local RESERVED_GROUPS = { "Normal", "Comment", "DiagnosticError", "DiagnosticWarn", "DiagnosticOk" }
local palette_cache = { key = nil, groups = {}, assigned = {}, used = {} }

--- Hue (0-360) and chroma (0-1: how far from grey; near-white text has little) of a 0xRRGGBB
--- colour.
---@param c integer
---@return number hue, number chroma
local function hue_sat(c)
  local r, g, b = math.floor(c / 65536) % 256 / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local d = max - min
  if d == 0 then
    return 0, 0
  end
  local h
  if max == r then
    h = ((g - b) / d) % 6
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, d
end

--- Distinct-coloured highlight groups for projects, for the current colour scheme: one per
--- clearly different hue (two cyans count as one), none that's grey.
---@return string[]
function M.palette()
  local key = (vim.g.colors_name or "") .. "/" .. vim.o.background .. "/" .. tostring(vim.o.termguicolors)
  if palette_cache.key == key then
    return palette_cache.groups
  end
  local gui = vim.o.termguicolors
  local function colour(name)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    return gui and h.fg or h.ctermfg
  end
  local kept = {} -- colours (or hues, in the GUI) already taken
  local function distinct(c)
    if not gui then
      return not kept[c]
    end
    local hue, sat = hue_sat(c)
    if sat < 0.3 then
      return false -- greyish: reads as plain text
    end
    for _, k in ipairs(kept) do
      local d = math.abs(hue - k)
      if math.min(d, 360 - d) < 20 then
        return false
      end
    end
    return true
  end
  local function keep(c)
    if gui then
      table.insert(kept, (hue_sat(c)))
    else
      kept[c] = true
    end
  end
  for _, g in ipairs(RESERVED_GROUPS) do
    local c = colour(g)
    if c and (gui and (select(2, hue_sat(c)) >= 0.3) or not gui) then
      keep(c)
    end
  end
  local groups = {}
  for _, g in ipairs(PALETTE_GROUPS) do
    local c = colour(g)
    if c and distinct(c) then
      keep(c)
      table.insert(groups, g)
    end
  end
  palette_cache = { key = key, groups = groups, assigned = {}, used = {} }
  return groups
end

---@param name string
---@return integer
local function hash(name)
  local h = 5381
  for i = 1, #name do
    h = (h * 33 + name:byte(i)) % 4294967296
  end
  return h
end

--- Give the journal's projects their colours in one go (sorted, each in its hash's slot or the
--- next free one), so the projects you have get different colours while there are enough.
---@param root string
function M.assign_colours(root)
  local palette = M.palette()
  if #palette == 0 then
    return
  end
  local names = M.known(root, { archived = true })
  table.sort(names)
  for _, name in ipairs(names) do
    M.auto_hl(name)
  end
end

--- A project's automatic colour: the same name always gets the same palette colour, unless
--- another project already took it (then the next free one).
---@param name string
---@return string? group
function M.auto_hl(name)
  local palette = M.palette()
  if #palette == 0 then
    return nil -- a scheme without distinct colours: the plain project colour
  end
  local group = "LogposeProject_" .. name:gsub("[^%w]", "_")
  local slot = palette_cache.assigned[name]
  if not slot then
    local n = #palette
    slot = hash(name) % n + 1
    local tries = 0
    while palette_cache.used[slot] and tries < n do
      slot, tries = slot % n + 1, tries + 1
    end
    if tries == n then
      slot = hash(name) % n + 1 -- more projects than colours: share
    end
    palette_cache.assigned[name], palette_cache.used[slot] = slot, true
  end
  vim.api.nvim_set_hl(0, group, { link = palette[slot], default = false })
  return group
end

--- Highlight group for a project's colour (nil when its page sets none).
---@param root string
---@param name string
---@param pages? table<string, logpose.ProjectPage>
---@return string?
function M.hl(root, name, pages)
  if root and not next(palette_cache.assigned) then
    M.assign_colours(root)
  end
  local page = (pages or M.pages(root))[name]
  local color = page and page.color
  if not color then
    return M.auto_hl(name)
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
    require("logpose.board").show(root)
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

  -- no name: the projects screen, where <CR> switches
  config.with_root(ui.safely(function(root)
    require("logpose.projects").open(root)
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

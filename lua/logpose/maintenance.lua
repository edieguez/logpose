--- Keep tags and projects tidy: `:Logpose rename-tag[!] old new`, `:Logpose rename-project[!] old new`.
--- Both show a preview and ask first (`!` skips it) and never touch files with unsaved changes.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local index = require("logpose.index")
local ui = require("logpose.util.ui")

local M = {}

---@param name string
---@return string
local function norm(name)
  return (name:gsub("^#", "")):lower()
end

--- Replace inline `#old` tags (case-insensitive, whole tag) in a line.
---@param line string
---@param old string normalized
---@param new string
---@return string line, integer count
function M.replace_tag(line, old, new)
  local count = 0
  local out = (" " .. line):gsub("([%s%(%[,;])#([%w_][%w_%-/]*)", function(pre, tag)
    local core, tail = tag:match("^(.-)([%-/]*)$")
    if core:lower() == old then
      count = count + 1
      return pre .. "#" .. new .. tail
    end
    return nil
  end)
  return out:sub(2), count
end

--- Rewrite a frontmatter `tags:` line, renaming `old` to `new`.
---@param line string
---@param old string
---@param new string
---@return string line, integer count
local function replace_fm_tags(line, old, new)
  local list = line:match("^tags:%s*%[(.*)%]%s*$")
  local inline = not list and line:match("^tags:%s*(.-)%s*$")
  local raw = list or inline
  if not raw or raw == "" then
    return line, 0
  end
  local count, items = 0, {}
  for item in raw:gmatch("[^,]+") do
    local v = vim.trim(item)
    local bare = v:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"):gsub("^#", "")
    if bare:lower() == old then
      count = count + 1
      v = new
    end
    table.insert(items, v)
  end
  if count == 0 then
    return line, 0
  end
  return list and ("tags: [" .. table.concat(items, ", ") .. "]") or ("tags: " .. table.concat(items, ", ")), count
end

---@class logpose.Change
---@field path string
---@field content? string  new content (nil when only moved)
---@field count integer
---@field move_to? string

--- Plan a tag rename over every note.
---@param root string
---@param old string
---@param new string
---@return logpose.Change[]
function M.plan_tag(root, old, new)
  old, new = norm(old), norm(new)
  local changes = {}
  for _, path in ipairs(index.files(root)) do
    local lines = fs.read_lines(path) or {}
    local total, in_fm = 0, lines[1] == "---"
    for i, line in ipairs(lines) do
      local n
      if in_fm and i > 1 and line == "---" then
        in_fm = false
      elseif in_fm and line:match("^tags:") then
        lines[i], n = replace_fm_tags(line, old, new)
        total = total + n
      elseif not in_fm then
        lines[i], n = M.replace_tag(line, old, new)
        total = total + n
      end
    end
    if total > 0 then
      table.insert(changes, { path = path, content = table.concat(lines, "\n"), count = total })
    end
  end
  return changes
end

--- Plan a project rename: frontmatter `project:`, #tags, the meeting folder, the project page,
--- and links pointing into them.
---@param root string
---@param old string
---@param new string
---@return logpose.Change[]
function M.plan_project(root, old, new)
  local project = require("logpose.project")
  old, new = project.normalize(old) or old, project.normalize(new)
  if not new then
    error("logpose: invalid new project name", 0)
  end
  local link = require("logpose.link")
  local moves = {}
  local meetings_old = fs.join(config.path("meetings", root), old)
  local meetings_new = fs.join(config.path("meetings", root), new)
  local page_old = fs.join(config.path("projects", root), old .. ".md")
  local page_new = fs.join(config.path("projects", root), new .. ".md")
  local rel_prefixes = {}
  if config.get().meeting_subdir:find("{project}", 1, true) and fs.is_dir(meetings_old) then
    if fs.exists(meetings_new) then
      error(("logpose: %s already exists"):format(link.relpath(root, meetings_new)), 0)
    end
    moves[meetings_old] = meetings_new
    table.insert(rel_prefixes, { link.relpath(root, meetings_old) .. "/", link.relpath(root, meetings_new) .. "/" })
  end
  if fs.exists(page_old) then
    if fs.exists(page_new) then
      error(("logpose: %s already exists"):format(link.relpath(root, page_new)), 0)
    end
    moves[page_old] = page_new
    local o, n = link.relpath(root, page_old):gsub("%.md$", ""), link.relpath(root, page_new):gsub("%.md$", "")
    table.insert(rel_prefixes, { o, n })
  end

  local changes = {}
  for _, path in ipairs(index.files(root)) do
    local lines = fs.read_lines(path) or {}
    local total, in_fm = 0, lines[1] == "---"
    for i, line in ipairs(lines) do
      local n = 0
      if in_fm and i > 1 and line == "---" then
        in_fm = false
      elseif in_fm and line:match("^project:%s*") then
        if vim.trim(line:gsub("^project:%s*", "")):lower() == old then
          lines[i], n = "project: " .. new, 1
        end
      elseif in_fm and line:match("^tags:") then
        lines[i], n = replace_fm_tags(line, old, new)
      elseif in_fm and line:match("^series:%s*" .. vim.pesc(old) .. "/") then
        lines[i], n = line:gsub("^(series:%s*)" .. vim.pesc(old) .. "/", "%1" .. new .. "/"), 1
      elseif not in_fm then
        lines[i], n = M.replace_tag(line, old, new)
        -- Links into the moved folder / page (wiki paths and markdown relative paths).
        for _, pair in ipairs(rel_prefixes) do
          local o, nw = pair[1], pair[2]
          local is_dir = o:sub(-1) == "/"
          -- A page path must end there (so projects/acme doesn't match projects/acme-api).
          local tail = is_dir and "()" or "([|%]%.#)>])"
          local before = lines[i]
          lines[i] = lines[i]
            :gsub("%[%[" .. vim.pesc(o) .. tail, function(t)
              return "[[" .. nw .. (type(t) == "string" and t or "")
            end)
            :gsub("(%]%(<?[%./]*)" .. vim.pesc(o) .. tail, function(pre, t)
              return pre .. nw .. (type(t) == "string" and t or "")
            end)
          if is_dir then
            -- markdown links from sibling folders (../acme/x.md)
            local o_base, n_base = vim.fs.basename(o:sub(1, -2)), vim.fs.basename(nw:sub(1, -2))
            lines[i] = lines[i]:gsub("(%]%(<?%.%./)" .. vim.pesc(o_base) .. "/", "%1" .. n_base .. "/")
          end
          if lines[i] ~= before then
            n = n + 1
          end
        end
      end
      total = total + n
    end
    if total > 0 then
      table.insert(changes, { path = path, content = table.concat(lines, "\n"), count = total })
    end
  end
  for from, to in pairs(moves) do
    table.insert(changes, { path = from, move_to = to, count = 0 })
  end
  table.sort(changes, function(a, b)
    return a.path < b.path
  end)
  return changes
end

--- Apply a plan: content changes first (atomic writes), then moves.
---@param changes logpose.Change[]
function M.apply(changes)
  local paths = {}
  for _, c in ipairs(changes) do
    if c.content then
      table.insert(paths, c.path)
    end
  end
  local ok, err = fs.check_writable(paths)
  if not ok then
    error(err, 0)
  end
  for _, c in ipairs(changes) do
    if c.content then
      local wrote, werr = fs.write_file(c.path, c.content)
      if not wrote then
        error(werr, 0)
      end
    end
  end
  for _, c in ipairs(changes) do
    if c.move_to then
      fs.mkdir_p(vim.fs.dirname(c.move_to))
      local moved, merr = (vim.uv or vim.loop).fs_rename(c.path, c.move_to)
      if not moved then
        error(("logpose: cannot move %s: %s"):format(c.path, merr), 0)
      end
    end
  end
  index.clear_cache()
end

---@param root string
---@param changes logpose.Change[]
---@param title string
---@param bang boolean
---@param after? fun()
local function confirm_and_apply(root, changes, title, bang, after)
  if #changes == 0 then
    require("logpose.util.ui").notify("logpose: nothing to change", vim.log.levels.INFO)
    return
  end
  local rel = require("logpose.link").relpath
  local function done()
    M.apply(changes)
    if after then
      after()
    end
    require("logpose.util.ui").notify(
      ("logpose: %s: updated %d file%s"):format(title, #changes, #changes == 1 and "" or "s"),
      vim.log.levels.INFO
    )
  end
  if bang then
    return done()
  end
  local lines = { title, "" }
  for _, c in ipairs(changes) do
    if c.move_to then
      table.insert(lines, ("  move %s → %s"):format(rel(root, c.path), rel(root, c.move_to)))
    else
      table.insert(lines, ("  %s (%d change%s)"):format(rel(root, c.path), c.count, c.count == 1 and "" or "s"))
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.cmd(("botright %dsplit"):format(math.min(#lines, 20)))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.ui.select(
    { "Apply", "Cancel" },
    { prompt = title .. "?" },
    ui.safely(function(choice)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if choice == "Apply" then
        done()
      else
        require("logpose.util.ui").notify("logpose: cancelled", vim.log.levels.INFO)
      end
    end)
  )
end

---@param opts logpose.CommandOpts
---@return string old, string new
local function two_args(opts, usage)
  if #opts.args ~= 2 then
    error("logpose: usage :Logpose " .. usage, 0)
  end
  return opts.args[1], opts.args[2]
end

---@param opts logpose.CommandOpts
function M.rename_tag_command(opts)
  local old, new = two_args(opts, "rename-tag[!] old new")
  if not new:gsub("^#", ""):match("^[%w_][%w_%-/]*$") then
    error(("logpose: invalid tag %q"):format(new), 0)
  end
  config.with_root(ui.safely(function(root)
    confirm_and_apply(root, M.plan_tag(root, old, new), ("Rename #%s → #%s"):format(norm(old), norm(new)), opts.bang)
  end))
end

---@param opts logpose.CommandOpts
function M.rename_project_command(opts)
  local old, new = two_args(opts, "rename-project[!] old new")
  config.with_root(ui.safely(function(root)
    local project = require("logpose.project")
    local o, n = project.normalize(old) or old, project.normalize(new) or new
    confirm_and_apply(
      root,
      M.plan_project(root, old, new),
      ("Rename project %s → %s"):format(o, n),
      opts.bang,
      function()
        if require("logpose.state").get("project") == o then
          require("logpose.state").set("project", n)
        end
        for dir, name in pairs(config.get().projects.paths) do
          if project.normalize(name) == o then
            require("logpose.util.ui").notify(
              ("logpose: update projects.paths[%q] = %q in your config"):format(dir, n),
              vim.log.levels.WARN
            )
          end
        end
      end
    )
  end))
end

function M.complete_tags(_, args)
  if #args > 0 then
    return {}
  end
  local root = config.resolve_root()
  if not root then
    return {}
  end
  return vim.tbl_map(function(c)
    return c.tag
  end, index.tag_counts(index.build(root)))
end

function M.complete_projects(_, args)
  if #args > 0 then
    return {}
  end
  local root = config.resolve_root()
  return root and require("logpose.search").projects(root, index.build(root)) or {}
end

return M

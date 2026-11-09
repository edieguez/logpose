--- Project docs: decisions, specs, runbooks and other docs that belong to one project and live in
--- its folder, `projects/<project>/<slug>.md`, next to the project page. `:Logpose doc [type]`
--- opens the new-doc form; moving a doc to another project moves the file (links follow);
--- promoting one makes it a lasting note in `notes/`.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

--- Doc types, sorted by `order` then name.
---@return { key: string, spec: table }[]
function M.types()
  local out = {}
  for key, spec in pairs(config.get().doc_types) do
    if spec then
      table.insert(out, { key = key, spec = spec })
    end
  end
  table.sort(out, function(a, b)
    local oa, ob = a.spec.order or math.huge, b.spec.order or math.huge
    if oa ~= ob then
      return oa < ob
    end
    return a.key < b.key
  end)
  return out
end

--- A doc type's settings (nil when it isn't one).
---@param key? string
---@return table?
function M.spec(key)
  local spec = key and config.get().doc_types[key]
  return spec or nil
end

--- The first doc type ("decision" by default).
---@return string
function M.default_type()
  local types = M.types()
  return types[1] and types[1].key or "doc"
end

--- A project's folder: `projects/<project>/`.
---@param root string
---@param project string
---@return string
function M.dir(root, project)
  local page = require("logpose.project").pages(root)[project]
  if page and page.in_archive then
    return fs.join(vim.fs.dirname(page.path), project) -- archived: projects/archive/<project>/
  end
  return fs.join(config.path("projects", root), project)
end

--- Where a doc titled `title` goes in `project`'s folder (`<slug>-2.md`… when the name's taken).
---@param root string
---@param project string
---@param title string
---@return string
function M.path(root, project, title)
  local slug = text.slugify(title)
  slug = slug ~= "" and slug or "doc"
  local dir = M.dir(root, project)
  return fs.titled_path(title, function(n)
    return fs.join(dir, (n and (slug .. "-" .. n) or slug) .. ".md")
  end)
end

--- Create a doc (without opening it). Returns its path, where the cursor goes, and whether it
--- existed already (then it's left as it is).
---@param root string
---@param d { type: string, title: string, project: string, tags?: string[], status?: string }
---@return string path, integer[]? cursor, boolean existed
function M.create(root, d)
  local spec = M.spec(d.type)
  if not spec then
    error(("logpose: %q isn't a doc type"):format(tostring(d.type)), 0)
  end
  local project = require("logpose.project").normalize(d.project or "")
  if not project then
    error("logpose: a doc belongs to a project", 0)
  end
  local path = M.path(root, project, d.title)
  if fs.exists(path) then
    return path, nil, true
  end
  local template = require("logpose.template")
  local fmt = require("logpose.frontmatter")
  local date = require("logpose.util.date")
  local rendered = template.render(
    template.load(spec.template or "doc", root),
    template.vars(date.today(), { title = d.title, project = project, type = d.type })
  )
  local lines = {
    "---",
    "title: " .. fmt.quote(d.title),
    "type: " .. d.type,
    "project: " .. project,
  }
  local status = text.nonempty(d.status) or (spec.statuses and spec.statuses[1])
  if status then
    table.insert(lines, "status: " .. status)
  end
  table.insert(lines, "tags: " .. fmt.render("tags", d.tags or {}))
  vim.list_extend(lines, require("logpose.timestamps").lines())
  table.insert(lines, "---")
  local body, cursor = require("logpose.markdown").tidy_text(
    table.concat(lines, "\n") .. "\n" .. rendered.text,
    { rendered.cursor[1] + #lines, rendered.cursor[2] }
  )
  local ok, err = fs.write_file(path, body)
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  return path, cursor, false
end

--- Move a note to `dest` with its frontmatter changed (`fm`, see `frontmatter.set`) and the
--- links to it fixed; `body(lines)` may change it too. The folder it leaves is removed if empty.
---@param root string
---@param path string
---@param dest string
---@param fm table
---@param body? fun(lines: string[]): string[]
---@return string dest
local function relocate(root, path, dest, fm, body)
  local link = require("logpose.link")
  local maintenance = require("logpose.maintenance")
  if dest == path then
    return path
  end
  if fs.exists(dest) then
    error(("logpose: %s already exists"):format(link.relpath(root, dest)), 0)
  end
  local buf = fs.find_buf(path)
  if buf and vim.bo[buf].modified then
    error("logpose: the doc has unsaved changes; save it first", 0)
  end
  local pair = maintenance.link_pair(root, path, dest)
  local changes = {}
  local lines = require("logpose.frontmatter").set(fs.read_lines(path) or {}, fm)
  if body then
    lines = body(lines)
  end
  table.insert(changes, { path = path, content = table.concat(lines, "\n"), count = 1 })
  for _, file in ipairs(require("logpose.index").files(root)) do
    if file ~= path then
      local flines = fs.read_lines(file) or {}
      local n = 0
      for i, l in ipairs(flines) do
        local nl, moved = maintenance.rewrite_links(l, { pair })
        if moved > 0 then
          flines[i], n = nl, n + 1
        end
      end
      if n > 0 then
        table.insert(changes, { path = file, content = table.concat(flines, "\n"), count = n })
      end
    end
  end
  table.insert(changes, { path = path, move_to = dest, count = 0 })
  table.insert(changes, { path = vim.fs.dirname(path), rmdir = true, count = 0 }) -- if it's empty now
  maintenance.apply(changes)
  return dest
end

--- Move a doc to another project's folder, its `project:` and the links to it following.
---@param root string
---@param path string
---@param to string the project
---@return string new_path
function M.move(root, path, to)
  return relocate(root, path, fs.join(M.dir(root, to), vim.fs.basename(path)), { project = to })
end

--- Make a doc a lasting note: it moves to `notes/` (links follow), leaves its project, type and
--- status behind, and says where it started ("Started in [[projects/acme|Acme]].").
---@param root string
---@param path string
---@return string new_path
function M.promote(root, path)
  local index = require("logpose.index")
  if index.file_type(path, root) ~= "doc" then
    error("logpose: this isn't a project doc", 0)
  end
  local item = index.index_lines(path, fs.read_lines(path) or {}, root)[1]
  local project = item.project
  local dest = require("logpose.notes.topic").note_path(root, item.title)
  local page = project and require("logpose.project").page_path(root, project)
  return relocate(root, path, dest, { project = false, type = false, status = false }, function(lines)
    if not project then
      return lines
    end
    local close = require("logpose.frontmatter").close(lines) or 0
    local title = require("logpose.project").title(root, project)
    local line = ("Started in %s."):format(require("logpose.link").make(dest, page, title, root))
    local out = vim.list_slice(lines, 1, close)
    vim.list_extend(out, { line, "" })
    local rest = vim.list_slice(lines, close + 1)
    while rest[1] == "" do
      table.remove(rest, 1)
    end
    return vim.list_extend(out, rest)
  end)
end

--- `:Logpose promote` in a doc: ask, then make it a lasting note (`!`: without asking).
---@param root string
---@param path string
---@param bang? boolean
---@param done? fun(path: string)
function M.promote_ask(root, path, bang, done)
  local function go()
    local dest = M.promote(root, path)
    local rel = require("logpose.link").relpath(root, dest)
    ui.notify(("logpose: now a lasting note: %s"):format(rel), vim.log.levels.INFO)
    if done then
      done(dest)
    end
  end
  if bang then
    return go()
  end
  local yes = "Move it to notes/ (it leaves the project; links follow)"
  vim.ui.select({ yes, "Cancel" }, { prompt = "Make it a lasting note?" }, function(choice)
    if choice == yes then
      ui.safely(go)()
    end
  end)
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local args = vim.deepcopy(opts.args)
  local kind = args[1] and M.spec(args[1]) and table.remove(args, 1) or nil
  local title = vim.trim(table.concat(args, " "))
  config.with_root(ui.safely(function(root)
    local project = require("logpose.project").resolve(root)
    require("logpose.edit").open_new_note(root, "doc", {
      type = kind,
      title = title ~= "" and title or nil,
      project = project,
    })
  end))
end

---@return string[]
function M.complete(_, args)
  if #args == 0 then
    return vim.tbl_map(function(t)
      return t.key
    end, M.types())
  end
  return {}
end

return M

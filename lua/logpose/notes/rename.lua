--- Renaming a note: a new title, and the file named after it, with every link to it following.
--- Topic notes and project docs keep their folder; a meeting keeps its date and time and starts a
--- series of its own when its title named the old one (an ad-hoc meeting's); a person's page goes
--- through `rename-person`. Tasks keep their file names (to-dos link to them and the board's undo
--- restores them by name), daily notes are named by their date and a project page by its project.
--- The edit form asks after a title change (`offer`); `:Logpose rename` and `R` in the notes and
--- meetings lists rename right away.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

--- Why a kind of note keeps its name, for the message when you try.
M.KEEPS = {
  task = "a task keeps its file name: to-dos link to it, and the board's undo restores it by name",
  daily = "a daily note is named by its date",
  project = "a project page is named by its project: rename the project with R in :Logpose projects",
}

--- Can notes of this kind be renamed?
---@param kind string
---@return boolean
function M.renamable(kind)
  return kind == "topic" or kind == "doc" or kind == "meeting" or kind == "person" or kind == "other"
end

--- A free path in the same folder: `name(nil)`, else `name(2)`, `name(3)`… (`path`, the note
--- itself, counts as free).
---@param path string
---@param name fun(n?: integer): string
---@return string
local function free(path, name)
  local dest, n = name(), 2
  while dest ~= path and fs.exists(dest) do
    dest, n = name(n), n + 1
  end
  return dest
end

--- Where the note at `path` goes once titled `new` (`old`: its title before), or nil when its
--- name stays (the same slug, or a kind that keeps its name).
---@param root string
---@param path string
---@param kind string
---@param old string
---@param new string
---@return string?
function M.target(root, path, kind, old, new)
  local slug = text.slugify(vim.trim(new or ""))
  if slug == "" or not M.renamable(kind) then
    return nil
  end
  local dir, base = vim.fs.dirname(path), vim.fs.basename(path)
  local dest
  if kind == "person" then
    dest = require("logpose.people").page_path(root, vim.trim(new))
    return dest ~= path and dest or nil
  elseif kind == "meeting" then
    -- the date (and time) stay: only the part the title gave changes
    local old_slug = text.slugify(vim.trim(old or ""))
    local s, e
    if old_slug ~= "" then
      local from = 1
      while true do
        local a, b = base:find(old_slug, from, true)
        if not a then
          break
        end
        s, e, from = a, b, a + 1
      end
    end
    local stem
    if s then
      local suffix = base:sub(e + 1):match("^%-%d+") or "" -- a -2 kept apart from another note
      local before, after = base:sub(1, s - 1), base:sub(e + 1 + #suffix)
      stem = function(n)
        return fs.join(dir, before .. (n and (slug .. "-" .. n) or slug) .. after)
      end
    else
      local fm = require("logpose.index").frontmatter(fs.read_lines(path) or {})
      local iso = type(fm.date) == "string" and fm.date or base:match("%d%d%d%d%-%d%d%-%d%d")
      local hh, mm
      if type(fm.created) == "string" then
        hh, mm = fm.created:match("T(%d%d):(%d%d)")
      end
      local time = hh and (hh .. mm) or nil
      local meeting = require("logpose.notes.meeting")
      stem = function(n)
        return fs.join(dir, meeting.filename(iso or "", n and (slug .. "-" .. n) or slug, fm.type or "", time))
      end
    end
    dest = free(path, stem)
  else
    dest = free(path, function(n)
      return fs.join(dir, (n and (slug .. "-" .. n) or slug) .. ".md")
    end)
  end
  return dest ~= path and dest or nil
end

--- The series a meeting retitled `title` belongs to: a new one when its title named the old
--- (an ad-hoc meeting's), else its own (a retro's is its type; a 1:1's, the person).
---@param fm table its frontmatter
---@param title string
---@return string? series nil: unchanged
local function new_series(fm, title)
  local key = type(fm.type) == "string" and fm.type or nil
  local spec = key and config.get().meeting_types[key]
  if not spec or not spec.prompt or spec.person then
    return nil
  end
  local slug = text.slugify(title)
  if slug == "" then
    return nil
  end
  local project = type(fm.project) == "string" and fm.project ~= "" and fm.project or nil
  return (project and (project .. "/") or "") .. key .. "-" .. slug
end

--- What renaming the note at `path` (title `old`) to `new` changes: its frontmatter, its own
--- links, the links to it everywhere, the move. Nothing is written.
---@param root string
---@param path string
---@param kind string
---@param old string
---@param new string
---@return logpose.Change[] changes, string dest, { old?: string, new?: string } series
function M.plan(root, path, kind, old, new)
  local dest = M.target(root, path, kind, old, new)
  if not dest then
    error("logpose: the file name stays the same", 0)
  end
  local maintenance = require("logpose.maintenance")
  local index = require("logpose.index")
  local files = index.files(root)
  local pair = maintenance.link_pair(root, path, dest, files)
  local lines = fs.read_lines(path) or {}
  if lines[#lines] == "" then
    table.remove(lines)
  end
  local fm = index.frontmatter(lines)
  local set = { title = vim.trim(new) }
  local series = {}
  if kind == "meeting" then
    local s = new_series(fm, new)
    if s and s ~= fm.series then
      -- a series of its own: the links to its old neighbours go, and are worked out again after
      series = { old = fm.series, new = s }
      set.series, set.previous, set.next = s, false, false
    end
  end
  lines = require("logpose.frontmatter").set(lines, set)
  local code = require("logpose.markdown").code_rows(lines)
  for i, l in ipairs(lines) do
    if not code[i] then
      lines[i] = maintenance.rewrite_links(l, { pair }, path)
    end
  end
  local changes = { { path = path, content = table.concat(lines, "\n") .. "\n", count = 1 } }
  for _, file in ipairs(files) do
    if file ~= path then
      local flines = fs.read_lines(file) or {}
      local n = 0
      for i, l in ipairs(flines) do
        local nl, moved = maintenance.rewrite_links(l, { pair }, file)
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
  return changes, dest, series
end

--- Rename the note at `path` (title `old`) to `new`: title, file and links. Returns where it is
--- now and how many other notes had links to it.
---@param root string
---@param path string
---@param kind string
---@param old string
---@param new string
---@return string dest, integer links
function M.apply(root, path, kind, old, new)
  local buf = fs.find_buf(path)
  if buf and vim.bo[buf].modified then
    error("logpose: the note has unsaved changes; save it first", 0)
  end
  if kind == "person" then
    local changes = require("logpose.people.rename").plan(root, vim.fn.fnamemodify(path, ":t:r"), new, { was = old })
    require("logpose.maintenance").apply(changes)
    local links = 0
    for _, c in ipairs(changes) do
      links = links + ((c.content and c.path ~= path) and 1 or 0)
    end
    return require("logpose.people").page_path(root, vim.trim(new)) or path, links
  end
  local changes, dest, series = M.plan(root, path, kind, old, new)
  require("logpose.maintenance").apply(changes)
  if series.new and config.get().series.links then
    -- both series' previous/next links, as `:Logpose relink` would make them
    local chain = require("logpose.notes.chain")
    require("logpose.maintenance").apply(chain.plan(root, { series = { series.old or "", series.new } }))
  end
  require("logpose.index").clear_cache()
  return dest, #changes - 2
end

--- "renamed to notes/queue-v2.md, fixing 3 links to it".
---@param root string
---@param dest string
---@param links integer
---@return string
local function said(root, dest, links)
  local rel = require("logpose.link").relpath(root, dest)
  if links > 0 then
    return ("logpose: renamed to %s, fixing links in %d note%s"):format(rel, links, links == 1 and "" or "s")
  end
  return "logpose: renamed to " .. rel
end

--- After the form saved a new title: ask whether the file follows it. `done(dest)` runs once it's
--- renamed. Says nothing when the name would stay.
---@param root string
---@param path string
---@param kind string
---@param old string
---@param new string
---@param done? fun(dest: string)
function M.offer(root, path, kind, old, new, done)
  local dest = M.target(root, path, kind, old, new)
  if not dest then
    return
  end
  local rel = require("logpose.link").relpath
  local yes = ("Rename the file to %s"):format(rel(root, dest))
  vim.ui.select(
    { yes, "Keep the file name" },
    { prompt = ("“%s” has a new title: rename %s too?"):format(vim.trim(new), vim.fs.basename(path)) },
    ui.safely(function(choice)
      if choice ~= yes then
        return
      end
      local moved, links = M.apply(root, path, kind, old, new)
      ui.notify(said(root, moved, links), vim.log.levels.INFO)
      if done then
        done(moved)
      end
    end)
  )
end

--- The note's title as logpose shows it (a person's name).
---@param path string
---@param kind string
---@return string
function M.title_of(path, kind)
  local fm = require("logpose.index").frontmatter(fs.current_lines(path) or {})
  local v = kind == "person" and fm.name or fm.title
  return type(v) == "string" and v ~= "" and v or vim.fn.fnamemodify(path, ":t:r")
end

--- Ask for a new title and rename (`:Logpose rename` without one, `R` in the lists).
---@param root string
---@param path string
---@param done? fun(dest: string)
---@param title? string  the new title, not asked when given
function M.ask(root, path, done, title)
  local kind = require("logpose.index").file_type(path, root)
  if M.KEEPS[kind] then
    error("logpose: " .. M.KEEPS[kind], 0)
  end
  local old = M.title_of(path, kind)
  local function go(new)
    new = new and vim.trim(new) or ""
    if new == "" or new == old then
      return
    end
    local dest, links
    if M.target(root, path, kind, old, new) then
      dest, links = M.apply(root, path, kind, old, new)
    else
      -- the same file name: only the title changes
      local ok, err = fs.update_lines(path, function(lines)
        return require("logpose.frontmatter").set(lines, { [kind == "person" and "name" or "title"] = new })
      end, { tidy = true })
      if not ok then
        error(err, 0)
      end
      require("logpose.index").clear_cache()
      dest, links = path, 0
    end
    ui.notify(
      dest ~= path and said(root, dest, links) or ("logpose: retitled “%s” (the file name stays)"):format(new),
      vim.log.levels.INFO
    )
    if done then
      done(dest)
    end
  end
  if title then
    return go(title)
  end
  vim.ui.input({ prompt = "New title: ", default = old }, ui.safely(go))
end

--- `:Logpose rename [title]`: rename the note you're in (asks for the title without one).
---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    local name = vim.api.nvim_buf_get_name(0)
    local path = name ~= "" and fs.in_root(name, root) or nil
    if not path then
      error("logpose: :Logpose rename works on a journal note", 0)
    end
    if vim.bo.modified then
      error("logpose: save the note first", 0)
    end
    local title = vim.trim(table.concat(opts.args, " "))
    M.ask(root, path, nil, title ~= "" and title or nil)
  end))
end

return M

--- The frontmatter editor's model: which fields a note has, reading and writing them, checking
--- what was typed (returning a message instead of failing, so the form can show it as you
--- type), and describing what saving will do.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")

local M = {}

--- Fields offered per note type, in order (keys a note already has are shown too).
M.FIELDS = {
  task = { "title", "status", "project", "tags", "due", "blocked" },
  meeting = { "title", "type", "date", "project", "attendees" },
  project = { "title", "description", "paths", "color" },
  topic = { "title", "project", "tags" },
  other = { "title", "project", "tags" },
}

--- Fields of a new task (`context` is a line under `## Context`, not frontmatter).
M.NEW_FIELDS = { "title", "status", "project", "tags", "due", "blocked", "context" }

--- Fields a bulk edit of tasks offers (a title is per task).
M.BULK_FIELDS = { "status", "project", "tags", "due", "blocked" }

--- Keys logpose maintains itself: shown, not editable.
M.MANAGED = {
  created = true,
  modified = true,
  started = true,
  done = true,
  series = true,
  order = true,
  merged_into = true,
  archived = true,
}

--- Keys whose value is a list (`[a, b]` in the file, `a, b` in the form).
M.LISTS = { tags = true, attendees = true, paths = true }

--- Keys holding a date.
M.DATES = { due = true, date = true }

--- Keys with a fixed set of values: `<CR>` picks one and `<C-a>`/`<C-x>` cycle through them.
M.CHOICES = { status = true, type = true, project = true }

--- What to type, shown in an empty field.
M.HINTS = {
  title = "a short title",
  status = "<CR> to pick · <C-a>/<C-x> to cycle",
  project = "<CR> to pick, or type a name",
  tags = "comma-separated · <Tab> completes",
  due = "today, fri, +3d, 2026-10-30",
  date = "today, -1d, 2026-10-14",
  blocked = "what it's waiting on (empty: not blocked)",
  attendees = "names, comma-separated · <Tab> completes",
  type = "<CR> to pick",
  description = "one line about the project",
  paths = "repo folders, comma-separated",
  color = "#rrggbb or a highlight group",
  context = "a line of context (optional)",
}

--- In a bulk edit: an empty field leaves each task as it is.
M.BULK_HINTS = {
  status = "unchanged · <CR> to pick",
  project = "unchanged · <CR> to pick · none removes it",
  tags = "unchanged · a, b replaces · +a -b adds or removes",
  due = "unchanged · today, fri, +3d · none clears it",
  blocked = "unchanged · a reason blocks · none unblocks",
}

M.read = require("logpose.frontmatter").read

--- Current lines of a note: its buffer when loaded, else the file.
---@param path string
---@return string[]
function M.note_lines(path)
  local buf = fs.find_buf(path)
  if buf and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return fs.read_lines(path) or {}
end

--- A list value as typed ("a, #b") split into items.
---@param key string
---@param text string
---@return string[]
function M.split(key, text)
  local items = {}
  for item in text:gmatch("[^,]+") do
    item = vim.trim(item)
    if key == "tags" then
      item = item:gsub("^#", "")
    end
    if item ~= "" then
      table.insert(items, item)
    end
  end
  return items
end

--- A value as the form shows it.
---@param v string|string[]|nil
---@return string
function M.text(v)
  if type(v) == "table" then
    return table.concat(v, ", ")
  end
  return v or ""
end

--- Equal as far as the file is concerned (nil, "" and {} are all "empty").
---@param a string|string[]|nil
---@param b string|string[]|nil
---@return boolean
function M.same(a, b)
  local function norm(v)
    if type(v) == "table" then
      return table.concat(v, "\0")
    end
    return v or ""
  end
  return norm(a) == norm(b)
end

---@class logpose.EditModel
---@field root string
---@field kind string            task | meeting | project | topic | other
---@field keys string[]          editable fields, in form order
---@field old table<string, string|string[]>  values as read (single note)
---@field info { key: string, value: string }[]  managed fields, shown for reference
---@field path? string           the note (single edit)
---@field title string           shown in the window's border
---@field bulk? { paths: string[], olds: table<string, table<string, string|string[]>> }
---@field initial table<string, string>  the form's starting text per field

--- The model for one note.
---@param path string
---@param root string
---@return logpose.EditModel
function M.load(path, root)
  local kind = require("logpose.index").note_type(path, root)
  kind = M.FIELDS[kind] and kind or "other"
  local entries = M.read(M.note_lines(path))
  local old, keys, seen, info = {}, {}, {}, {}
  for _, e in ipairs(entries) do
    old[e.key] = e.value
  end
  local function add(key)
    if not seen[key] and not M.MANAGED[key] then
      seen[key] = true
      table.insert(keys, key)
    end
  end
  for _, key in ipairs(M.FIELDS[kind]) do
    add(key)
  end
  for _, e in ipairs(entries) do
    add(e.key)
    if M.MANAGED[e.key] and e.value ~= "" then
      table.insert(info, { key = e.key, value = M.text(e.value) })
    end
  end
  local initial = {}
  for _, key in ipairs(keys) do
    initial[key] = M.text(old[key])
  end
  local title = type(old.title) == "string" and old.title ~= "" and old.title or vim.fs.basename(path)
  return { root = root, kind = kind, keys = keys, old = old, info = info, path = path, title = title, initial = initial }
end

--- The model for a task that doesn't exist yet: the form starts from `defaults` (the column,
--- the detected project…) and saving creates the file.
---@param root string
---@param defaults? { title?: string, status?: string, project?: string, tags?: string[], due?: string }
---@return logpose.EditModel
function M.load_new(root, defaults)
  defaults = defaults or {}
  local initial = {
    title = defaults.title or "",
    status = defaults.status or config.get().tasks.capture_status,
    project = defaults.project or "",
    tags = table.concat(defaults.tags or {}, ", "),
    due = defaults.due or "",
    blocked = "",
    context = "",
  }
  return {
    root = root,
    kind = "task",
    keys = vim.deepcopy(M.NEW_FIELDS),
    old = {},
    info = {},
    title = "New task",
    new = true,
    initial = initial,
  }
end

--- The model for several task files: a field all of them share starts with that value, a
--- field where they differ starts empty ("leave as is").
---@param paths string[]
---@param root string
---@return logpose.EditModel
function M.load_bulk(paths, root)
  local olds = {}
  for _, p in ipairs(paths) do
    local o = {}
    for _, e in ipairs(M.read(M.note_lines(p))) do
      o[e.key] = e.value
    end
    olds[p] = o
  end
  local initial, common = {}, {}
  for _, key in ipairs(M.BULK_FIELDS) do
    local first = M.text(olds[paths[1]][key])
    local all_same = true
    for _, p in ipairs(paths) do
      if M.text(olds[p][key]) ~= first then
        all_same = false
      end
    end
    initial[key] = all_same and first or ""
    common[key] = all_same
  end
  return {
    root = root,
    kind = "task",
    keys = vim.deepcopy(M.BULK_FIELDS),
    old = {},
    info = {},
    title = ("%d tasks"):format(#paths),
    bulk = { paths = paths, olds = olds, common = common },
    initial = initial,
  }
end

--- What a date in the form means: "Fri 16 Oct · due tomorrow" for a due date (worded as on the
--- board), "Wed 14 Oct · yesterday" for another date.
---@param iso string
---@param key string
---@return string
function M.describe_date(iso, key)
  local today = date.today()
  local rel = key == "due" and (date.due(iso, today)) or date.relative(iso, today)
  return date.short(iso, today) .. " · " .. rel
end

---@class logpose.EditCtx
---@field root string
---@field known table<string, boolean>  known projects
---@field people? table<string, boolean>  known person slugs (filled on first use)

---@param root string
---@return logpose.EditCtx
function M.context(root)
  local known = {}
  for _, name in ipairs(require("logpose.project").known(root, { archived = true })) do
    known[name] = true
  end
  return { root = root, known = known }
end

--- Check what was typed in one field. Returns the value to save (normalised), or an error
--- message; and a note shown beside a valid value (what a date means, a project's name).
---@param kind string
---@param key string
---@param text string
---@param ctx logpose.EditCtx
---@return string|string[] value, string? err, string? note
function M.check(kind, key, text, ctx)
  text = vim.trim(text)
  if M.LISTS[key] then
    local list = M.split(key, text)
    if key == "attendees" or key == "with" then
      -- a name nobody has used yet: a new person, or a typo
      local slugify = require("logpose.util.text").slugify
      ctx.people = ctx.people
        or (function()
          local set = {}
          for _, p in ipairs(require("logpose.people").known(ctx.root)) do
            set[p.slug] = true
          end
          return set
        end)()
      local new = vim.tbl_filter(function(n)
        return not ctx.people[slugify(n)]
      end, type(list) == "table" and list or { list })
      if #new > 0 then
        return list, nil, "new: " .. table.concat(new, ", ")
      end
    end
    return list, nil, nil
  end
  if text == "" then
    if key == "title" and (kind == "task" or kind == "meeting" or kind == "project") then
      return "", "a title is needed"
    end
    return "", nil, nil
  end
  if key == "status" and kind == "task" then
    local taskfile = require("logpose.taskfile")
    for _, c in ipairs(taskfile.columns()) do
      if c.key == text:lower() or c.label:lower() == text:lower() then
        -- the column's name, unless that's what was typed
        return c.key, nil, c.label:lower() ~= text:lower() and c.label or nil
      end
    end
    return text, "not a board column · <CR> to pick"
  elseif key == "project" then
    local slug = require("logpose.project").normalize(text)
    if not slug then
      return text, "use letters or digits"
    end
    local notes = {}
    if slug ~= text then
      table.insert(notes, "saved as " .. slug)
    end
    if not ctx.known[slug] then
      table.insert(notes, "new project")
    else
      local title = require("logpose.project").title(ctx.root, slug)
      if title ~= slug and title ~= text then
        table.insert(notes, title)
      end
    end
    return slug, nil, #notes > 0 and table.concat(notes, " · ") or nil
  elseif M.DATES[key] then
    local iso = (key == "due" and date.resolve_due or date.resolve)(text)
    if not iso then
      return text, "not a date: try " .. M.HINTS[key]
    end
    return iso, nil, M.describe_date(iso, key)
  elseif key == "type" and kind == "meeting" then
    local spec = config.get().meeting_types[text]
    if not spec then
      return text, "not a meeting type · <CR> to pick"
    end
    return text, nil, spec.label
  elseif key == "color" then
    if text:match("^#%x%x%x%x%x%x$") or vim.fn.hlexists(text) == 1 then
      return text, nil, nil
    end
    return text, "use #rrggbb or a highlight group"
  end
  return text, nil, nil
end

---@class logpose.EditResult
---@field values table<string, any>   checked values per field
---@field errors table<string, string>
---@field notes table<string, string>
---@field changed table<string, any>  what saving writes (single: new values; bulk: see below)
---@field nerrors integer

--- Check every field of the form and work out what changed.
--- In a bulk edit, `changed` holds only fields the user set: `project`/`due`/`blocked` may be
--- "" (from `none`), and `tags` may be `{ add = {...}, remove = {...} }`.
---@param model logpose.EditModel
---@param texts table<string, string>  the form's text per field
---@param ctx logpose.EditCtx
---@return logpose.EditResult
function M.collect(model, texts, ctx)
  local r = { values = {}, errors = {}, notes = {}, changed = {}, nerrors = 0 }
  for _, key in ipairs(model.keys) do
    local text = texts[key] or ""
    local value, err, note
    if model.bulk then
      local trimmed = vim.trim(text)
      if trimmed == vim.trim(model.initial[key] or "") then
        value = nil -- left as it was
      elseif trimmed:lower() == "none" and (key == "project" or key == "due" or key == "blocked") then
        value, note = "", key == "blocked" and "unblocks them" or "clears it"
      elseif key == "tags" and trimmed:match("^[+-]") then
        local delta, ok = { add = {}, remove = {} }, true
        for item in trimmed:gmatch("%S+") do
          local sign, tag = item:match("^([+-])#?([%w_][%w_%-/]*),?$")
          if not sign then
            ok = false
          elseif sign == "+" then
            table.insert(delta.add, tag)
          else
            table.insert(delta.remove, tag)
          end
        end
        if ok then
          value = delta
          local parts = {}
          if #delta.add > 0 then
            table.insert(parts, "adds " .. table.concat(delta.add, ", "))
          end
          if #delta.remove > 0 then
            table.insert(parts, "removes " .. table.concat(delta.remove, ", "))
          end
          note = table.concat(parts, " · ")
        else
          value, err = trimmed, "use +tag and -tag, or a list to replace them"
        end
      elseif trimmed == "" then
        -- emptied a shared value: the same as typing none (a task always has a status)
        if key == "tags" then
          value = {}
        elseif key ~= "status" then
          value = ""
        end
      else
        value, err, note = M.check(model.kind, key, text, ctx)
      end
      if value ~= nil and not err then
        r.changed[key] = value
      end
    else
      value, err, note = M.check(model.kind, key, text, ctx)
      if model.new and key == "title" and vim.trim(text) == "" then
        err = nil -- a new task's title: asked for on save, not shouted at while you start typing
      end
      if not err and model.kind == "project" and key == "project" and not M.same(model.old[key], value) then
        err = "rename a project with R in :Logpose projects (it updates every note)"
      end
      if not err and not M.same(model.old[key], value) then
        -- an absent key left empty stays absent
        if not (model.old[key] == nil and M.same(value, "")) then
          r.changed[key] = value
        end
      end
    end
    r.values[key] = value
    if err then
      r.errors[key] = err
      r.nerrors = r.nerrors + 1
    end
    r.notes[key] = note
  end
  return r
end

--- What saving a new task will do.
---@param r logpose.EditResult
---@return string[]
function M.new_effects(r)
  local v = r.values
  local taskfile = require("logpose.taskfile")
  local status = (v.status ~= nil and v.status ~= "" and not r.errors.status) and v.status
    or config.get().tasks.capture_status
  local line = ("create it in %s"):format(taskfile.label(status) or status)
  if type(v.project) == "string" and v.project ~= "" and not r.errors.project then
    line = line .. ", for " .. v.project
  end
  if status == config.get().board.start then
    line = line .. ", setting started"
  end
  local out = { line }
  if type(v.tags) == "table" and #v.tags > 0 then
    table.insert(out, "tagged " .. table.concat(v.tags, ", "))
  end
  if type(v.due) == "string" and v.due ~= "" and not r.errors.due then
    table.insert(out, (date.due(v.due)))
  end
  if type(v.blocked) == "string" and v.blocked ~= "" then
    table.insert(out, "blocked: " .. v.blocked)
  end
  return out
end

--- What saving will do, one short line each.
---@param model logpose.EditModel
---@param r logpose.EditResult
---@param links_to? fun(): integer  how many links point at the note (for a meeting move)
---@return string[]
function M.effects(model, r, links_to)
  if model.new then
    return M.new_effects(r)
  end
  local out = {}
  local changed = r.changed
  local board = config.get().board
  local taskfile = require("logpose.taskfile")
  local plain = {}
  local who = model.bulk and ("%d tasks"):format(#model.bulk.paths) or "it"
  for _, key in ipairs(model.keys) do
    local v = changed[key]
    if v ~= nil then
      if model.kind == "task" and key == "status" and v ~= "" then
        local line = ("move %s to %s"):format(who, taskfile.label(v))
        if v == board.start then
          line = line .. ", setting started"
        elseif v == board.done then
          line = line .. ", setting done"
        end
        table.insert(out, line .. " (logged)")
      elseif model.kind == "task" and key == "project" then
        local from = not model.bulk and model.old.project
        from = type(from) == "string" and from ~= "" and from or nil
        if v == "" then
          table.insert(out, from and ("remove it from %s (logged)"):format(from) or "remove the project (logged)")
        else
          table.insert(out, ("project %s→ %s (logged)"):format(from and (from .. " ") or "", v))
        end
      elseif model.kind == "task" and key == "blocked" then
        table.insert(out, v == "" and ("unblock %s (logged)"):format(who) or ("block %s (logged)"):format(who))
      elseif model.kind == "meeting" and key == "project" then
        local dir = require("logpose.link").relpath(
          model.root,
          require("logpose.notes.meeting").dir(model.root, v ~= "" and v or nil)
        )
        local n = links_to and links_to() or 0
        table.insert(
          out,
          ("move the note to %s/%s"):format(
            dir,
            n > 0 and (", fixing %d link%s to it"):format(n, n == 1 and "" or "s") or ""
          )
        )
      else
        table.insert(plain, key)
      end
    end
  end
  if #plain > 0 then
    table.insert(out, "update " .. table.concat(plain, ", "))
  end
  return out
end

return M

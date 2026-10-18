--- Meeting notes: `:Logpose meeting [type] [YYYY-MM-DD]`.
local config = require("logpose.config")
local daily = require("logpose.notes.daily")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local link = require("logpose.link")
local template = require("logpose.template")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

--- Enabled meeting types, sorted by `order` then name.
---@return { key: string, spec: table }[]
function M.types()
  local out = {}
  for key, spec in pairs(config.get().meeting_types) do
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

---@param key string
---@return table
local function get_type(key)
  local spec = config.get().meeting_types[key]
  if not spec then
    local names = vim.tbl_map(function(t)
      return t.key
    end, M.types())
    error(("logpose: unknown meeting type %q. Valid: %s"):format(key, table.concat(names, ", ")), 0)
  end
  return spec
end

--- Meeting filename for the given parts (with .md).
---@param iso string
---@param slug string
---@param key string
---@param time? string HHMM
---@return string
function M.filename(iso, slug, key, time)
  return template.substitute(config.get().meeting_filename, {
    date = iso,
    time = time or date.now_hhmm(),
    slug = slug,
    type = key,
  }) .. ".md"
end

---@class logpose.MeetingNote
---@field key string
---@field title string
---@field slug string
---@field series string
---@field date string
---@field project? string
---@field path string
---@field content string
---@field cursor integer[]
---@field previous? logpose.Item  previous note in the series
---@field carried logpose.Item[]   open tasks carried over from it

--- Build (but don't write) a meeting note.
---@param root string
---@param key string meeting type
---@param input? string answer to the type's prompt
---@param iso string
---@param project? string active project
---@param attendees? string[]
---@return logpose.MeetingNote
function M.build(root, key, input, iso, project, attendees)
  local spec = get_type(key)
  local title
  if spec.title then
    title = text.trim(template.substitute(spec.title, { input = input or "" }))
  end
  if not title or title == "" then
    title = input or spec.label or key
  end

  local slug = text.slugify(title)
  if slug == "" then
    slug = text.slugify(key) ~= "" and text.slugify(key) or "meeting"
  end

  -- Recurring meetings share a series: the type, plus the prompt answer when there is one
  -- (so each person gets their own 1:1 series).
  local series = key
  if spec.prompt and input then
    local s = text.slugify(input)
    if s ~= "" then
      series = key .. "-" .. s
    end
  end
  if project then
    series = project .. "/" .. series -- recurring meetings never mix across projects
  end

  -- People: a person-type answer (1:1) is also an attendee.
  attendees = vim.deepcopy(attendees or {})
  local with
  if spec.person and input then
    with = input
    local present = false
    for _, a in ipairs(attendees) do
      present = present or text.slugify(a) == text.slugify(input)
    end
    if not present then
      table.insert(attendees, 1, input)
    end
  end

  local vars = template.vars(iso, {
    title = title,
    type = key,
    type_label = spec.label or key,
    attendees = table.concat(attendees, ", "),
    series = series,
    previous = "",
    project = project or "",
  })
  local rendered = template.render(template.load(spec.template or "meeting", root), vars)

  local frontmatter = { "---", "type: " .. key, "date: " .. iso }
  if project then
    table.insert(frontmatter, "project: " .. project)
  end
  local fmt = require("logpose.frontmatter")
  table.insert(frontmatter, "title: " .. fmt.quote(title))
  if with then
    table.insert(frontmatter, "with: " .. fmt.quote(with))
  end
  table.insert(frontmatter, "attendees: " .. fmt.render("attendees", attendees))
  table.insert(frontmatter, "series: " .. series)
  vim.list_extend(frontmatter, require("logpose.timestamps").lines())
  table.insert(frontmatter, "---")

  local path = fs.join(M.dir(root, project), M.filename(iso, slug, key))
  local body = vim.split(rendered.text, "\n", { plain = true })
  local cursor = { rendered.cursor[1], rendered.cursor[2] }
  local previous, carried = M.previous(root, series, iso, path)
  if previous then
    local inserted = M.series_lines(path, previous, carried, root)
    -- Right after the title heading (or at the top).
    local h = 0
    for i, line in ipairs(body) do
      if line:match("^#%s") then
        h = i
        break
      end
    end
    for i, line in ipairs(inserted) do
      table.insert(body, h + i, line)
    end
    if cursor[1] > h then
      cursor[1] = cursor[1] + #inserted
    end
  end

  local content, final_cursor = require("logpose.markdown").tidy_text(
    table.concat(frontmatter, "\n") .. "\n" .. table.concat(body, "\n"),
    { cursor[1] + #frontmatter, cursor[2] }
  )
  return {
    key = key,
    title = title,
    slug = slug,
    series = series,
    date = iso,
    project = project,
    path = path,
    content = content,
    cursor = final_cursor,
    previous = previous,
    carried = carried,
  }
end

--- Most recent earlier note of `series` and its open tasks.
---@param root string
---@param series string
---@param iso string
---@param path string the new note (excluded)
---@return logpose.Item? previous, logpose.Item[] open_tasks
function M.previous(root, series, iso, path)
  local items = require("logpose.index").build(root)
  local best
  for _, it in ipairs(items) do
    if it.kind == "note" and it.note_type == "meeting" and it.series == series and it.date and it.file ~= path then
      local earlier = it.date < iso or (it.date == iso and it.file < path)
      if earlier and (not best or it.date > best.date or (it.date == best.date and it.file > best.file)) then
        best = it
      end
    end
  end
  local open = {}
  if best and config.get().series.carry_over then
    for _, it in ipairs(items) do
      if it.kind == "task" and it.file == best.file and not it.checked then
        table.insert(open, it)
      end
    end
  end
  return best, open
end

--- "Previous: …" and the "## Carried over" section for a new note at `path`.
---@param path string
---@param previous logpose.Item
---@param carried logpose.Item[]
---@param root string
---@return string[]
function M.series_lines(path, previous, carried, root)
  local label = previous.date and (previous.title .. " " .. previous.date) or previous.title
  local lines = { "", "Previous: " .. link.make(path, previous.file, label, root) }
  if #carried > 0 then
    vim.list_extend(lines, { "", "## Carried over" })
    local from = link.make(path, previous.file, previous.date or previous.title, root)
    for _, it in ipairs(carried) do
      -- Drop an older "(from …)" so items carried several times keep one, current, origin.
      local text = it.text:gsub("%s*%(from %[%[.-%]%]%)$", ""):gsub("%s*%(from %[.-%]%(.-%)%)$", "")
      table.insert(lines, ("- [ ] %s (from %s)"):format(text, from))
    end
  end
  return lines
end

--- Mark carried tasks in the previous note as `- [>]` (migrated), so they aren't listed twice.
---@param note logpose.MeetingNote
---@return "file"|"buffer"|nil
function M.mark_carried(note)
  if not note.previous or #note.carried == 0 or not config.get().series.mark_carried then
    return nil
  end
  local rows = {}
  for _, it in ipairs(note.carried) do
    rows[it.lnum] = true
  end
  local ok, err, changed = fs.update_lines(note.previous.file, function(lines)
    local touched = false
    for lnum in pairs(rows) do
      local line = lines[lnum]
      if line and line:match("^%s*[-*+]%s+%[ %]") then
        lines[lnum] = line:gsub("%[ %]", "[>]", 1)
        touched = true
      end
    end
    return touched and lines or nil
  end)
  if not ok then
    error(err, 0)
  end
  return changed
end

--- Directory for meeting notes of `project` (see `meeting_subdir`).
---@param root string
---@param project? string
---@return string
function M.dir(root, project)
  local base = config.path("meetings", root)
  local sub = template.substitute(config.get().meeting_subdir, { project = project or "" })
  local parts = vim.tbl_filter(function(p)
    return p ~= "" and p ~= "." and p ~= ".."
  end, vim.split(sub, "/", { plain = true }))
  if #parts == 0 then
    return base
  end
  return fs.join(base, unpack(parts))
end

--- Existing notes for the same date/slug/type when the filename includes {time}.
---@param root string
---@param note logpose.MeetingNote
---@return string[] paths, oldest first
function M.find_same(root, note)
  local sentinel = "\1TIME\1"
  local name = M.filename(note.date, note.slug, note.key, sentinel)
  local pattern = "^" .. vim.pesc(name):gsub(vim.pesc(vim.pesc(sentinel)), "%%d%%d%%d%%d") .. "$"
  local dir = vim.fs.dirname(note.path)
  local found = {}
  if fs.is_dir(dir) then
    for entry, kind in vim.fs.dir(dir) do
      if kind == "file" and entry:match(pattern) then
        table.insert(found, fs.join(dir, entry))
      end
    end
  end
  table.sort(found)
  return found
end

--- Insert `item` at the end of the `## <heading>` section (created at the end if missing).
--- Returns nil when a line in that section matches `marker` (plain substring or predicate).
---@param lines string[]
---@param heading string
---@param item string
---@param marker string|fun(line: string): boolean
---@return string[]?
function M.insert_under_heading(lines, heading, item, marker)
  local out = vim.list_extend({}, lines)
  local h
  for i, l in ipairs(out) do
    if l:match("^##%s+(.-)%s*$") == heading then
      h = i
      break
    end
  end
  if not h then
    while #out > 0 and out[#out] == "" do
      table.remove(out)
    end
    if #out > 0 then
      table.insert(out, "")
    end
    table.insert(out, "## " .. heading)
    table.insert(out, item)
    return out
  end

  local stop = #out + 1
  for i = h + 1, #out do
    if out[i]:match("^##?%s") then
      stop = i
      break
    end
  end
  local last = h
  for i = h + 1, stop - 1 do
    local dup
    if type(marker) == "function" then
      dup = marker(out[i])
    else
      dup = out[i]:find(marker, 1, true) ~= nil
    end
    if dup then
      return nil
    end
    if out[i] ~= "" then
      last = i
    end
  end
  table.insert(out, last + 1, item)
  if out[last + 2] and out[last + 2]:match("^#") then
    table.insert(out, last + 2, "")
  end
  return out
end

--- Add a link to the meeting under `## Meetings` in that day's daily note.
---@param root string
---@param note logpose.MeetingNote
---@return "file"|"buffer"|nil changed
function M.link_in_daily(root, note)
  local daily_path = daily.ensure(note.date, root)
  local prefix = note.project and (note.project .. ": ") or ""
  local item = "- " .. prefix .. link.make(daily_path, note.path, note.title, root)
  local target = link.target(daily_path, note.path, root)
  -- Exact target match, so "retro" doesn't match "retro-2" or another project's "retro".
  local function marker(line)
    for _, form in ipairs({
      "[[" .. target .. "|",
      "[[" .. target .. "]]",
      "(" .. target .. ")",
      "(<" .. target .. ">)",
    }) do
      if line:find(form, 1, true) then
        return true
      end
    end
    return false
  end
  local ok, err, changed = fs.update_lines(daily_path, function(lines)
    return M.insert_under_heading(lines, "Meetings", item, marker)
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
  return changed
end

---@param path string
---@param cursor? integer[]
local function open(path, cursor)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if cursor then
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
end

local safely = ui.safely

---@param root string
---@param note logpose.MeetingNote
local function write_and_open(root, note)
  local ok, err = fs.write_file(note.path, note.content, { tidy = true })
  if not ok then
    error(err, 0)
  end
  local marked, mark_err = pcall(M.mark_carried, note)
  if not marked then
    require("logpose.util.ui").notify(
      "logpose: couldn't mark carried items in the previous note: " .. tostring(mark_err),
      vim.log.levels.WARN
    )
  end
  local linked, link_err = pcall(M.link_in_daily, root, note)
  if not linked then
    require("logpose.util.ui").notify(
      "logpose: note created, but linking it in the daily note failed: " .. tostring(link_err),
      vim.log.levels.WARN
    )
  elseif link_err == "buffer" then
    require("logpose.util.ui").notify(
      "logpose: added the meeting link to the daily note buffer (unsaved)",
      vim.log.levels.INFO
    )
  end
  open(note.path, note.cursor)
end

--- Create (or open) a meeting note of type `key`.
---@param root string
---@param key string
---@param input? string
---@param iso string
---@param project? string
---@param attendees? string[]
function M.create(root, key, input, iso, project, attendees)
  local note = M.build(root, key, input, iso, project, attendees)
  if fs.exists(note.path) then
    open(note.path)
    return
  end
  if config.get().meeting_filename:find("{time}", 1, true) then
    local existing = M.find_same(root, note)
    if #existing > 0 then
      vim.ui.select(
        { "Open existing", "Create new" },
        {
          prompt = ("%s already has a note on %s"):format(note.title, note.date),
        },
        safely(function(choice)
          if choice == "Open existing" then
            open(existing[#existing])
          elseif choice == "Create new" then
            write_and_open(root, note)
          end
        end)
      )
      return
    end
  end
  write_and_open(root, note)
end

--- Type currently being prompted for (used by the completion functions below).
M._completing = nil

--- Past titles of the type being prompted (or people names for person types).
---@param arglead string
---@return string[]
function M.complete_titles(arglead)
  local key = M._completing
  local root = config.resolve_root()
  if not key or not root then
    return {}
  end
  local spec = config.get().meeting_types[key] or {}
  if spec.person then
    return require("logpose.people").complete(arglead)
  end
  local seen, out = {}, {}
  for _, it in ipairs(require("logpose.index").build(root)) do
    if it.kind == "note" and it.type == key and not seen[it.title] then
      seen[it.title] = true
      if vim.startswith(it.title:lower(), arglead:lower()) then
        table.insert(out, it.title)
      end
    end
  end
  table.sort(out)
  return out
end

_G.LogposeCompleteTitles = function(arglead)
  return M.complete_titles(arglead)
end

--- Ask for attendees when the type wants them, then create.
local function with_attendees(root, key, input, iso, project)
  local spec = get_type(key)
  if not spec.ask_attendees then
    M.create(root, key, input, iso, project)
    return
  end
  vim.ui.input(
    { prompt = "Attendees (comma separated): ", completion = "customlist,v:lua.LogposeCompletePeople" },
    safely(function(value)
      local attendees = {}
      for name in (value or ""):gmatch("[^,]+") do
        name = vim.trim(name):gsub("^@", "")
        if name ~= "" then
          table.insert(attendees, name)
        end
      end
      M.create(root, key, input, iso, project, attendees)
    end)
  )
end

--- Ask for the type's prompt (if any), then create the note.
---@param root string
---@param key string
---@param iso string
---@param project? string
function M.start(root, key, iso, project)
  local spec = get_type(key)
  if not spec.prompt then
    with_attendees(root, key, nil, iso, project)
    return
  end
  require("logpose.people") -- defines the completion globals
  M._completing = key
  vim.ui.input(
    { prompt = spec.prompt, completion = "customlist,v:lua.LogposeCompleteTitles" },
    safely(function(input)
      M._completing = nil
      input = input and text.trim(input) or ""
      if input == "" then
        require("logpose.util.ui").notify("logpose: cancelled (empty input)", vim.log.levels.INFO)
        return
      end
      with_attendees(root, key, input, iso, project)
    end)
  )
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local key, iso = opts.args[1], opts.args[2]
  if #opts.args > 2 then
    error("logpose: usage :Logpose meeting [type] [YYYY-MM-DD]", 0)
  end
  if key and (date.is_iso(key) or key == "today") then
    key, iso = nil, key
  end
  if iso == nil or iso == "today" then
    iso = date.today()
  elseif not date.is_iso(iso) then
    error(("logpose: invalid date %q (use YYYY-MM-DD)"):format(iso), 0)
  end
  if key then
    get_type(key) -- fail on an unknown type before any prompt
  end

  config.with_root(safely(function(root)
    local project = require("logpose.project").resolve(root)
    if key then
      M.start(root, key, iso, project)
      return
    end
    vim.ui.select(
      M.types(),
      {
        prompt = "Meeting type",
        format_item = function(t)
          return t.spec.label or t.key
        end,
      },
      safely(function(choice)
        if choice then
          M.start(root, choice.key, iso, project)
        end
      end)
    )
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

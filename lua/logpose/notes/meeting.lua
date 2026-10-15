--- Meeting notes: `:Logpose meeting [type] [YYYY-MM-DD]`.
local config = require("logpose.config")
local daily = require("logpose.notes.daily")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local link = require("logpose.link")
local template = require("logpose.template")
local text = require("logpose.util.text")

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

---@param s string
---@return string
local function yaml_string(s)
  local escaped = s:gsub("\\", "\\\\"):gsub('"', '\\"')
  return '"' .. escaped .. '"'
end

---@class logpose.MeetingNote
---@field key string
---@field title string
---@field slug string
---@field series string
---@field date string
---@field path string
---@field content string
---@field cursor integer[]

--- Build (but don't write) a meeting note.
---@param root string
---@param key string meeting type
---@param input? string answer to the type's prompt
---@param iso string
---@return logpose.MeetingNote
function M.build(root, key, input, iso)
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

  local vars = template.vars(iso, {
    title = title,
    type = key,
    type_label = spec.label or key,
    attendees = "",
    series = series,
    previous = "",
  })
  local rendered = template.render(template.load(spec.template or "meeting", root), vars)

  local frontmatter = {
    "---",
    "type: " .. key,
    "date: " .. iso,
    "title: " .. yaml_string(title),
    "attendees: []",
    "series: " .. series,
    "---",
  }
  return {
    key = key,
    title = title,
    slug = slug,
    series = series,
    date = iso,
    path = fs.join(config.path("meetings", root), M.filename(iso, slug, key)),
    content = table.concat(frontmatter, "\n") .. "\n" .. rendered.text,
    cursor = { rendered.cursor[1] + #frontmatter, rendered.cursor[2] },
  }
end

--- Existing notes for the same date/slug/type when the filename includes {time}.
---@param root string
---@param note logpose.MeetingNote
---@return string[] paths, oldest first
function M.find_same(root, note)
  local sentinel = "\1TIME\1"
  local name = M.filename(note.date, note.slug, note.key, sentinel)
  local pattern = "^" .. vim.pesc(name):gsub(vim.pesc(vim.pesc(sentinel)), "%%d%%d%%d%%d") .. "$"
  local dir = config.path("meetings", root)
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
--- Returns nil when a line in that section already contains `marker`.
---@param lines string[]
---@param heading string
---@param item string
---@param marker string
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
    if out[i]:find(marker, 1, true) then
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
  local item = "- " .. link.make(daily_path, note.path, note.title, root)
  local marker = vim.fn.fnamemodify(note.path, ":t:r")
  local ok, err, changed = fs.update_lines(daily_path, function(lines)
    return M.insert_under_heading(lines, "Meetings", item, marker)
  end)
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

---@param fn function
local function safely(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local msg = tostring(err)
      vim.notify(msg:find("^logpose:") and msg or ("logpose: " .. msg), vim.log.levels.ERROR)
    end
  end
end

---@param root string
---@param note logpose.MeetingNote
local function write_and_open(root, note)
  local ok, err = fs.write_file(note.path, note.content)
  if not ok then
    error(err, 0)
  end
  local linked, link_err = pcall(M.link_in_daily, root, note)
  if not linked then
    vim.notify(
      "logpose: note created, but linking it in the daily note failed: " .. tostring(link_err),
      vim.log.levels.WARN
    )
  elseif link_err == "buffer" then
    vim.notify("logpose: added the meeting link to the daily note buffer (unsaved)", vim.log.levels.INFO)
  end
  open(note.path, note.cursor)
end

--- Create (or open) a meeting note of type `key`.
---@param root string
---@param key string
---@param input? string
---@param iso string
function M.create(root, key, input, iso)
  local note = M.build(root, key, input, iso)
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

--- Ask for the type's prompt (if any), then create the note.
---@param root string
---@param key string
---@param iso string
function M.start(root, key, iso)
  local spec = get_type(key)
  if not spec.prompt then
    M.create(root, key, nil, iso)
    return
  end
  vim.ui.input(
    { prompt = spec.prompt },
    safely(function(input)
      input = input and text.trim(input) or ""
      if input == "" then
        vim.notify("logpose: cancelled (empty input)", vim.log.levels.INFO)
        return
      end
      M.create(root, key, input, iso)
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
  local root = config.root()

  if key then
    M.start(root, key, iso)
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
        M.start(root, choice.key, iso)
      end
    end)
  )
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

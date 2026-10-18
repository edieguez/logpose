--- `:Logpose edit`: a floating form for a note's frontmatter, with completion for each field.
--- Saving applies the changes the way logpose would: a task's status, project and blocker go
--- through the board's code (logged, `started`/`done` kept), dates accept `tomorrow` or `+3d`,
--- and moving a meeting to another project moves the note and fixes links to it.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.edit")

--- Fields offered per note type, in order (keys a note already has are shown too).
M.FIELDS = {
  task = { "title", "status", "project", "tags", "due", "blocked" },
  meeting = { "title", "type", "date", "project", "attendees" },
  project = { "title", "description", "paths", "color" },
  topic = { "title", "project", "tags" },
  other = { "title", "project", "tags" },
}

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

---@class logpose.FmEntry
---@field key string
---@field value string|string[]  as read (lists split, quotes removed)

--- The frontmatter as ordered entries, and the line of its closing `---` (nil if none).
---@param lines string[]
---@return logpose.FmEntry[], integer?
function M.read(lines)
  local entries = {}
  if lines[1] ~= "---" then
    return entries, nil
  end
  local index = require("logpose.index")
  for i = 2, #lines do
    if lines[i] == "---" then
      local fm = index.frontmatter(vim.list_slice(lines, 1, i))
      for j = 2, i - 1 do
        local key = lines[j]:match("^([%w_%-]+):")
        if key then
          table.insert(entries, { key = key, value = fm[key] or "" })
        end
      end
      return entries, i
    end
  end
  return {}, nil
end

---@param s string
---@return string
local function quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- A value as it goes in the frontmatter.
---@param key string
---@param value string|string[]
---@return string
function M.render(key, value)
  if type(value) == "table" then
    local items = vim.tbl_map(function(v)
      return v:find("[,:%[%]\"'#]") and quote(v) or v
    end, value)
    return "[" .. table.concat(items, ", ") .. "]"
  end
  if value == "" then
    return ""
  end
  if key == "title" or value:find(": ") or value:find("^[%[{&*!|>'\"%%@`#]") then
    return quote(value)
  end
  return value
end

--- Set or remove (nil) keys in frontmatter lines, keeping their order; new keys go last.
---@param lines string[]
---@param changes table<string, string|false> rendered values; false removes the key
---@return string[]
function M.apply_lines(lines, changes)
  local _, close = M.read(lines)
  if not close then
    local fm = { "---" }
    for key, v in pairs(changes) do
      if v then
        table.insert(fm, key .. ": " .. v)
      end
    end
    table.insert(fm, "---")
    return vim.list_extend(fm, lines)
  end
  local done = {}
  local out = { lines[1] }
  for i = 2, close - 1 do
    local key = lines[i]:match("^([%w_%-]+):")
    local v = key and changes[key]
    if v == nil then
      table.insert(out, lines[i])
    else
      done[key] = true
      if v then
        table.insert(out, v == "" and (key .. ":") or (key .. ": " .. v))
      end
    end
  end
  local new = {}
  for key, v in pairs(changes) do
    if not done[key] and v and v ~= "" then
      table.insert(new, key .. ": " .. v)
    end
  end
  table.sort(new)
  vim.list_extend(out, new)
  for i = close, #lines do
    table.insert(out, lines[i])
  end
  return out
end

--- Current lines of a note: its buffer when loaded, else the file.
---@param path string
---@return string[]
local function note_lines(path)
  local buf = fs.find_buf(path)
  if buf and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return fs.read_lines(path) or {}
end

--- The form's lines for a note.
---@param path string
---@param root string
---@return string[] lines, string kind, table<string, string|string[]> values
function M.form(path, root)
  local kind = require("logpose.index").note_type(path, root)
  kind = M.FIELDS[kind] and kind or "other"
  local entries = M.read(note_lines(path))
  local values, order, seen = {}, {}, {}
  for _, e in ipairs(entries) do
    values[e.key] = e.value
  end
  local function add(key)
    if not seen[key] and not M.MANAGED[key] then
      seen[key] = true
      table.insert(order, key)
    end
  end
  for _, key in ipairs(M.FIELDS[kind]) do
    add(key)
  end
  for _, e in ipairs(entries) do
    add(e.key)
  end
  local lines = {}
  for _, key in ipairs(order) do
    local v = values[key] or ""
    if type(v) == "table" then
      v = table.concat(v, ", ")
    end
    table.insert(lines, key .. ": " .. v)
  end
  local info = {}
  for _, e in ipairs(entries) do
    if M.MANAGED[e.key] and e.value ~= "" then
      local v = type(e.value) == "table" and table.concat(e.value, ", ") or e.value
      table.insert(info, ("# %s: %s"):format(e.key, v))
    end
  end
  if #info > 0 then
    table.insert(lines, "")
    vim.list_extend(lines, info)
  end
  return lines, kind, values
end

--- Parse the form back into values (lists split). Lines starting with # are ignored.
---@param lines string[]
---@return table<string, string|string[]>, string[] order
function M.parse_form(lines)
  local out, order = {}, {}
  for _, l in ipairs(lines) do
    if not l:match("^%s*#") and vim.trim(l) ~= "" then
      local key, value = l:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
      if not key then
        error(("logpose: can't read %q (expected key: value)"):format(l), 0)
      end
      if M.LISTS[key] then
        local items = {}
        for item in value:gmatch("[^,]+") do
          item = vim.trim(item)
          if key == "tags" then
            item = item:gsub("^#", "")
          end
          if item ~= "" then
            table.insert(items, item)
          end
        end
        out[key] = items
      else
        out[key] = value
      end
      table.insert(order, key)
    end
  end
  return out, order
end

---@param a string|string[]|nil
---@param b string|string[]|nil
local function same(a, b)
  if type(a) == "table" and type(b) == "table" then
    return table.concat(a, "\0") == table.concat(b, "\0")
  end
  return (a or "") == (b or "")
end

--- Check and normalise the new values; returns the changed keys.
---@param kind string
---@param old table<string, string|string[]>
---@param new table<string, string|string[]>
---@param root string
---@return table<string, string|string[]|false> changed (false: removed)
function M.validate(kind, old, new, root)
  local changed = {}
  for key, v in pairs(new) do
    if M.MANAGED[key] then
      error(("logpose: %s is kept by logpose and can't be edited here"):format(key), 0)
    end
    if key == "status" and v ~= "" then
      local taskfile = require("logpose.taskfile")
      local found
      for _, c in ipairs(taskfile.columns()) do
        if c.key == v:lower() or c.label:lower() == v:lower() then
          found = c.key
        end
      end
      if not found then
        local keys = vim.tbl_map(function(c)
          return c.key
        end, taskfile.columns())
        error(("logpose: unknown status %q (one of %s)"):format(v, table.concat(keys, ", ")), 0)
      end
      v = found
    elseif key == "project" and v ~= "" then
      local slug = require("logpose.project").normalize(v)
      if not slug then
        error(("logpose: invalid project name %q"):format(v), 0)
      end
      v = slug
    elseif M.DATES[key] and v ~= "" then
      local iso = date.resolve(v)
      if not iso then
        error(("logpose: %s: %q isn't a date (YYYY-MM-DD, today, tomorrow, +3d, +1w)"):format(key, v), 0)
      end
      v = iso
    elseif key == "type" and kind == "meeting" and v ~= "" and not config.get().meeting_types[v] then
      error(("logpose: unknown meeting type %q"):format(v), 0)
    elseif key == "title" and kind ~= "other" and kind ~= "topic" and v == "" then
      error("logpose: the title can't be empty", 0)
    end
    if not same(old[key], v) then
      changed[key] = v
    end
  end
  for key in pairs(old) do
    if new[key] == nil and not M.MANAGED[key] then
      changed[key] = false
    end
  end
  if kind == "project" and changed.project ~= nil then
    error("logpose: rename a project with R in :Logpose projects (it updates every note)", 0)
  end
  return changed
end

--- Move a meeting note to another project's folder: frontmatter, series, links to it (and the
--- `- project:` label of daily-note links).
---@param root string
---@param path string
---@param from? string
---@param to? string
---@return string new_path
local function move_meeting(root, path, from, to)
  local meeting = require("logpose.notes.meeting")
  local link = require("logpose.link")
  local maintenance = require("logpose.maintenance")
  local dest = fs.join(meeting.dir(root, to), vim.fs.basename(path))
  if dest == path then
    return path
  end
  if fs.exists(dest) then
    error(("logpose: %s already exists"):format(link.relpath(root, dest)), 0)
  end
  local buf = fs.find_buf(path)
  if buf and vim.bo[buf].modified then
    error("logpose: the note has unsaved changes; save it first", 0)
  end
  local rel_old = link.relpath(root, path):gsub("%.md$", "")
  local rel_new = link.relpath(root, dest):gsub("%.md$", "")
  local changes = {}
  -- the note itself: series follows the project
  local lines = fs.read_lines(path) or {}
  local entries = M.read(lines)
  for _, e in ipairs(entries) do
    if e.key == "series" and type(e.value) == "string" and e.value ~= "" then
      local rest = (from and e.value:match("^" .. vim.pesc(from) .. "/(.+)$")) or e.value
      local series = to and (to .. "/" .. rest) or rest
      lines = M.apply_lines(lines, { series = series })
    end
  end
  table.insert(changes, { path = path, content = table.concat(lines, "\n") .. "\n", count = 1 })
  for _, file in ipairs(require("logpose.index").files(root)) do
    if file ~= path then
      local flines = fs.read_lines(file) or {}
      local n = 0
      for i, l in ipairs(flines) do
        local nl, moved = maintenance.rewrite_links(l, { { rel_old, rel_new } })
        if moved > 0 then
          -- the daily note's "- acme: [[…]]" label
          if from then
            nl = nl:gsub("^(%s*[-*] )" .. vim.pesc(from) .. ": ", "%1" .. (to and (to .. ": ") or ""))
          elseif to then
            nl = nl:gsub("^(%s*[-*] )(%[%[)", "%1" .. to .. ": %2")
          end
          flines[i], n = nl, n + 1
        end
      end
      if n > 0 then
        table.insert(changes, { path = file, content = table.concat(flines, "\n") .. "\n", count = n })
      end
    end
  end
  table.insert(changes, { path = path, move_to = dest, count = 0 })
  -- the old project's meeting folder, if this was its last note (only removed when empty)
  table.insert(changes, { path = vim.fs.dirname(path), rmdir = true, count = 0 })
  maintenance.apply(changes)
  if buf then
    -- show the moved note where the old one was
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        vim.cmd.edit(vim.fn.fnameescape(dest))
      end)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  return dest
end

--- Write the changes to the note. Returns its path (a meeting may have moved).
---@param root string
---@param path string
---@param kind string
---@param changed table<string, string|string[]|false>
---@return string path, string[] keys changed
function M.save(root, path, kind, changed)
  local taskfile = require("logpose.taskfile")
  local keys = vim.tbl_keys(changed)
  table.sort(keys)
  if #keys == 0 then
    return path, keys
  end
  local special = {}
  if kind == "task" then
    for _, key in ipairs({ "status", "project", "blocked" }) do
      if changed[key] ~= nil then
        special[key] = changed[key]
        changed[key] = nil
      end
    end
  end
  local meeting_move
  if kind == "meeting" and changed.project ~= nil then
    local old = require("logpose.index").frontmatter(note_lines(path)).project
    meeting_move = { from = (old ~= "" and old) or nil, to = changed.project or nil }
    if meeting_move.to == "" then
      meeting_move.to = nil
    end
  end
  local rendered = {}
  for key, v in pairs(changed) do
    rendered[key] = v and M.render(key, v) or false
  end
  if next(rendered) then
    local ok, err = fs.update_lines(path, function(lines)
      return M.apply_lines(lines, rendered)
    end, { tidy = true })
    if not ok then
      error(err, 0)
    end
  end
  if special.status ~= nil and special.status ~= "" then
    taskfile.set_status(path, special.status)
  end
  if special.project ~= nil then
    taskfile.set_project(path, special.project ~= "" and special.project or nil)
  end
  if special.blocked ~= nil then
    taskfile.set_blocked(path, (special.blocked ~= "" and special.blocked) or nil)
  end
  if meeting_move then
    path = move_meeting(root, path, meeting_move.from, meeting_move.to)
  end
  require("logpose.index").clear_cache()
  if
    vim.tbl_contains(keys, "project")
    or vim.tbl_contains(keys, "paths")
    or (kind == "project" and vim.tbl_contains(keys, "title"))
  then
    require("logpose.project").changed()
  end
  return path, keys
end

-- Completion ---------------------------------------------------------------------------------

--- Candidates for `key`, as complete-items.
---@param root string
---@param kind string
---@param key string
---@param partial string
---@return table[]
function M.candidates(root, kind, key, partial)
  local items = {}
  local function add(word, menu)
    table.insert(items, { word = word, menu = menu })
  end
  if key == "project" then
    local project = require("logpose.project")
    for _, name in ipairs(project.known(root)) do
      local title = project.title(root, name)
      add(name, title ~= name and title or nil)
    end
  elseif key == "status" then
    for _, c in ipairs(require("logpose.taskfile").columns()) do
      add(c.key, c.label)
    end
  elseif key == "tags" then
    local index = require("logpose.index")
    for _, c in ipairs(index.tag_counts(index.build(root))) do
      add(c.tag, tostring(c.count))
    end
  elseif key == "attendees" or key == "with" then
    for _, p in ipairs(require("logpose.people").known(root)) do
      add(p.name, ("%d notes"):format(p.count))
    end
  elseif key == "type" and kind == "meeting" then
    for name, spec in pairs(config.get().meeting_types) do
      if spec then
        add(name, spec.label)
      end
    end
    table.sort(items, function(a, b)
      return a.word < b.word
    end)
  elseif M.DATES[key] then
    local today = date.today()
    for d = 0, 13 do
      local iso = date.add_days(today, d)
      local label = d == 0 and "today" or d == 1 and "tomorrow" or ("in %dd"):format(d)
      add(iso, date.weekday_name(iso):sub(1, 3) .. " · " .. label)
    end
  elseif key == "paths" then
    for _, dir in ipairs(vim.fn.getcompletion(partial ~= "" and partial or "~/", "dir")) do
      add((dir:gsub("/$", "")), nil)
    end
  end
  if partial == "" or key == "paths" then
    return items
  end
  local p = partial:lower()
  local starts, contains = {}, {}
  for _, it in ipairs(items) do
    local w = it.word:lower()
    if vim.startswith(w, p) then
      table.insert(starts, it)
    elseif w:find(p, 1, true) or (it.menu and it.menu:lower():find(p, 1, true)) then
      table.insert(contains, it)
    end
  end
  return vim.list_extend(starts, contains)
end

--- What to complete at the cursor: { col (0-based start), items }.
---@param buf integer
---@return integer?, table[]?
local function at_cursor(buf)
  local state = vim.b[buf].logpose_edit
  if not state then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local before = line:sub(1, col)
  if before:match("^%s*#") then
    return nil
  end
  local key = before:match("^%s*([%w_%-]+)%s*:")
  if not key then
    -- completing a field name
    local partial = before:match("^%s*([%w_%-]*)$")
    if not partial then
      return nil
    end
    local present = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      local k = l:match("^%s*([%w_%-]+)%s*:")
      if k then
        present[k] = true
      end
    end
    local items = {}
    local seen = {}
    for _, kind in ipairs({ state.kind, "task", "meeting", "project", "other" }) do
      for _, k in ipairs(M.FIELDS[kind] or {}) do
        if not present[k] and not seen[k] and vim.startswith(k, partial) then
          seen[k] = true
          table.insert(items, { word = k .. ": ", abbr = k })
        end
      end
    end
    return #before - #partial, items
  end
  local value_start = #(before:match("^%s*[%w_%-]+%s*:%s*"))
  local partial = before:sub(value_start + 1)
  local start = value_start
  if M.LISTS[key] then
    local last = partial:match("^.*,%s*()") -- after the last comma
    if last then
      start = value_start + last - 1
      partial = partial:sub(last)
    end
  end
  local items = M.candidates(state.root, state.kind, key, partial)
  if M.LISTS[key] then
    -- don't offer what's already in the list
    local have = {}
    for item in before:sub(value_start + 1):gmatch("[^,]+") do
      have[vim.trim(item):lower()] = true
    end
    items = vim.tbl_filter(function(it)
      return not have[it.word:lower()] or it.word:lower() == partial:lower()
    end, items)
  end
  return start, items
end

--- 'omnifunc' for the form (<C-x><C-o>).
function M.omnifunc(findstart, _)
  local buf = vim.api.nvim_get_current_buf()
  local start, items = at_cursor(buf)
  if findstart == 1 then
    return start or -3
  end
  return items or {}
end

--- Show the completion menu for the cursor position (as you type).
---@param buf integer
local function popup(buf)
  local start, items = at_cursor(buf)
  if not start or not items or #items == 0 then
    return
  end
  vim.fn.complete(start + 1, items)
end

-- The form -----------------------------------------------------------------------------------

--- Open the editor for `path`. `opts.on_save(new_path, keys)` runs after a save.
---@param path string
---@param opts? { root?: string, on_save?: fun(path: string, keys: string[]) }
---@return integer? win
function M.open(path, opts)
  opts = opts or {}
  local root = opts.root or config.root()
  path = fs.normalize(path)
  local lines, kind, old = M.form(path, root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modified = false
  pcall(vim.api.nvim_buf_set_name, buf, "logpose://edit/" .. vim.fs.basename(path))
  vim.bo[buf].filetype = "logpose-edit"
  vim.bo[buf].omnifunc = "v:lua.require'logpose.edit'.omnifunc"
  vim.b[buf].logpose_edit = { root = root, kind = kind, path = path }
  -- Our own popup, not a completion plugin's.
  vim.b[buf].completion = false -- blink.cmp
  if package.loaded["cmp"] then
    pcall(function()
      require("cmp").setup.buffer({ enabled = false })
    end)
  end

  local title = old.title
  title = type(title) == "string" and title ~= "" and title or vim.fs.basename(path)
  local width = math.min(math.max(60, vim.fn.strdisplaywidth(title) + 14), math.max(40, vim.o.columns - 8))
  local height = math.min(#lines + 1, math.max(6, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - 2 - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = " " .. require("logpose.board.text").fit(title, width - 4):gsub("%s+$", "") .. " ",
    title_pos = "center",
    footer = " <C-s> save · q cancel · <Tab> complete ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true

  local function highlight()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match("^%s*#") then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #l, hl_group = "Comment" })
      else
        local key_end = l:find(":")
        if key_end then
          vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = key_end, hl_group = "Identifier" })
        end
      end
    end
  end
  highlight()

  -- completeopt is global on Neovim 0.10: set it while the form has focus.
  local saved_cot
  local group = vim.api.nvim_create_augroup("logpose.edit." .. buf, { clear = true })
  local function enter()
    saved_cot = saved_cot or vim.o.completeopt
    vim.o.completeopt = "menuone,noinsert,noselect"
  end
  local function leave()
    if saved_cot then
      vim.o.completeopt = saved_cot
      saved_cot = nil
    end
  end
  enter()
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, { group = group, buffer = buf, callback = enter })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, { group = group, buffer = buf, callback = leave })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      leave()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      highlight()
      popup(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged" }, { group = group, buffer = buf, callback = highlight })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function save()
    local new = M.parse_form(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local changed = M.validate(kind, old, new, root)
    local new_path, keys = M.save(root, path, kind, changed)
    vim.bo[buf].modified = false
    close()
    if #keys == 0 then
      ui.notify("logpose: nothing changed", vim.log.levels.INFO)
    else
      ui.notify(("logpose: updated %s"):format(table.concat(keys, ", ")), vim.log.levels.INFO)
    end
    if opts.on_save then
      opts.on_save(new_path, keys)
    end
  end
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = ui.safely(save),
  })
  local function map(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map({ "n", "i" }, "<C-s>", function()
    vim.cmd("stopinsert")
    ui.safely(save)()
  end, "Save")
  map("n", "q", close, "Cancel")
  map("n", "<Esc>", close, "Cancel")
  vim.keymap.set("i", "<Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    vim.schedule(function()
      popup(buf)
    end)
    return ""
  end, { buffer = buf, expr = true, silent = true, desc = "Complete" })
  vim.keymap.set("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
  end, { buffer = buf, expr = true, silent = true, desc = "Previous" })
  vim.keymap.set("i", "<CR>", function()
    return vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected ~= -1 and "<C-y>" or "<CR>"
  end, { buffer = buf, expr = true, silent = true, desc = "Accept" })

  -- Start on the first value.
  local first = lines[1] or ""
  local c = first:find(":")
  pcall(vim.api.nvim_win_set_cursor, win, { 1, c and math.min(c + 1, #first) or 0 })
  return win
end

---@param _ logpose.CommandOpts
function M.command(_)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.bo.buftype ~= "" or not path:match("%.md$") then
    error("logpose: :Logpose edit works on a journal note (on the board, press e)", 0)
  end
  config.with_root(ui.safely(function(root)
    local p = fs.normalize(path)
    if not vim.startswith(p, fs.normalize(root) .. "/") then
      error("logpose: this note isn't in the journal", 0)
    end
    M.open(p, { root = root })
  end))
end

return M

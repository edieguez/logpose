--- `:Logpose notes [filters]`: the notes screen. Notes (meetings, topic notes, daily notes, project
--- pages) listed newest first, grouped by type or by project, for the active project or all of
--- them, with how many open to-dos each holds and how many tasks it's linked with. It's the notes'
--- counterpart of the board: tasks aren't listed here.
local config = require("logpose.config")
local date = require("logpose.util.date")
local text = require("logpose.board.text")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.notes")

--- Sections when grouping by type, in this order.
M.TYPES = {
  { key = "meeting", label = "Meetings" },
  { key = "topic", label = "Topic notes" },
  { key = "daily", label = "Daily notes" },
  { key = "project", label = "Project pages" },
  { key = "other", label = "Other notes" },
}

--- Rows a section shows before "… N more".
M.SHOWN = 8

--- Highlight groups (linked to your colour scheme; override them to taste).
M.HL = {
  LogposeNotesHeading = "Title",
  LogposeNotesDate = "Comment",
  LogposeNotesMeta = "Comment",
  LogposeNotesTodos = "DiagnosticWarn",
  LogposeNotesTasks = "Directory",
  LogposeNotesHint = "Comment",
}

M.HELP = {
  "logpose notes",
  "  <CR>   open the note (on a heading: fold / unfold; on “… more”: show all)",
  "  e      edit its details (frontmatter)",
  "  z      fold / unfold the section",
  "  /      filter (find filters: #tag, @person, type:retro, since:-7d…)",
  "  p      this project / all projects",
  "  g      group by type / by project",
  "  n      new topic note           d  today's daily note",
  "  b      board (tasks)            r  refresh",
  "  q      close                    ?  this help",
}

---@class logpose.NotesState
---@field root string
---@field buf integer
---@field project? string    the project shown (nil: all)
---@field filter string
---@field group "type"|"project"
---@field folded table<string, boolean>
---@field expanded table<string, boolean>
---@field rows table<integer, { file?: string, section?: string, more?: boolean, heading?: boolean }>

---@class logpose.NoteEntry
---@field item logpose.Item
---@field todos integer   open to-dos in it
---@field tasks integer   tasks linked with it (either way)
---@field when string     its date, or the day it was last edited

--- The notes to show, newest first, with their counts.
---@param root string
---@param opts { project?: string, filter?: string, today?: string }
---@return logpose.NoteEntry[]
function M.collect(root, opts)
  local index = require("logpose.index")
  local query = require("logpose.query")
  local today = opts.today or date.today()
  local q = query.parse(query.split(opts.filter or ""), today, true)
  local items = index.build(root)
  local todos = {}
  for _, it in ipairs(items) do
    if it.kind == "todo" and not it.checked then
      todos[it.file] = (todos[it.file] or 0) + 1
    end
  end
  local tasks = {}
  for _, notes in pairs(require("logpose.links").related(root, items)) do
    for _, n in ipairs(notes) do
      tasks[n.file] = (tasks[n.file] or 0) + 1
    end
  end
  local out = {}
  for _, it in ipairs(items) do
    if it.kind == "note" then
      local in_scope = not opts.project or it.project == opts.project or vim.tbl_contains(it.tags or {}, opts.project)
      if in_scope and query.match(it, q) then
        local when = it.date or (it.mtime and os.date("%Y-%m-%d", it.mtime)) or ""
        table.insert(out, { item = it, todos = todos[it.file] or 0, tasks = tasks[it.file] or 0, when = when })
      end
    end
  end
  table.sort(out, function(a, b)
    if a.when ~= b.when then
      return a.when > b.when
    end
    return (a.item.title or "") < (b.item.title or "")
  end)
  return out
end

--- One row's chunks: date, title, counts, and the project when it isn't obvious.
---@param e logpose.NoteEntry
---@param o { title_w: integer, show_project: boolean, show_type: boolean, project_hl: fun(name: string): string }
---@return { [1]: string, [2]?: string }[]
local function row(e, o)
  local it = e.item
  local title = it.file_type == "daily" and date.weekday_name(it.date or e.when) or (it.title or "")
  if o.show_type then
    local kind = it.file_type == "topic" and "note" or it.file_type
    title = (it.type and it.file_type == "meeting") and (it.type .. " · " .. title) or (kind .. " · " .. title)
  end
  local chunks = {
    { "  " },
    { (e.when ~= "" and e.when or "          "), "LogposeNotesDate" },
    { "  " },
    { text.fit(title, o.title_w) },
  }
  local meta = {}
  if e.todos > 0 then
    table.insert(meta, { ("☐ %d to-do%s"):format(e.todos, e.todos == 1 and "" or "s"), "LogposeNotesTodos" })
  end
  if e.tasks > 0 then
    table.insert(meta, { ("→ %d task%s"):format(e.tasks, e.tasks == 1 and "" or "s"), "LogposeNotesTasks" })
  end
  if o.show_project and it.project then
    table.insert(meta, { "◆ " .. it.project, o.project_hl(it.project) })
  end
  for i, m in ipairs(meta) do
    table.insert(chunks, { i == 1 and "  " or "  ·  ", "LogposeNotesMeta" })
    table.insert(chunks, m)
  end
  return chunks
end

--- The screen as lines of chunks, plus what each row leads to.
---@param s logpose.NotesState
---@param entries logpose.NoteEntry[]
---@param width integer
---@return { [1]: string, [2]?: string }[][], table<integer, table>
function M.build(s, entries, width)
  local project = require("logpose.project")
  local pages = project.pages(s.root)
  local function project_hl(name)
    return project.hl(s.root, name, pages) or "LogposeBoardProject"
  end
  local lines, rows = {}, {}
  local function add(chunks, r)
    table.insert(lines, chunks)
    rows[#lines] = r
  end
  local scope = s.project and project.title(s.root, s.project) or "all projects"
  add({ { "# Notes", "LogposeNotesHeading" }, { " · " .. scope, "LogposeNotesHeading" } })
  if s.filter ~= "" then
    add({ { "filter: " .. s.filter, "LogposeNotesHint" } })
  end

  -- sections
  local sections, by_key = {}, {}
  local function section(key, label)
    if not by_key[key] then
      by_key[key] = { key = key, label = label, entries = {} }
      table.insert(sections, by_key[key])
    end
    return by_key[key]
  end
  if s.group == "type" then
    for _, t in ipairs(M.TYPES) do
      section(t.key, t.label)
    end
    for _, e in ipairs(entries) do
      table.insert((by_key[e.item.file_type] or by_key.other).entries, e)
    end
  else
    local names = {}
    for _, e in ipairs(entries) do
      local key = e.item.project or ""
      if not by_key[key] then
        table.insert(names, key)
        by_key[key] = { key = key, entries = {} }
      end
      table.insert(by_key[key].entries, e)
    end
    table.sort(names, function(a, b)
      if (a == "") ~= (b == "") then
        return b == ""
      end
      return a < b
    end)
    for _, name in ipairs(names) do
      local sec = by_key[name]
      sec.label = name == "" and "No project" or project.title(s.root, name)
      table.insert(sections, sec)
    end
  end

  -- the title column is as wide as the longest title shown, within limits
  local longest = 0
  for _, sec in ipairs(sections) do
    local shown = s.expanded[sec.key] and #sec.entries or math.min(#sec.entries, M.SHOWN)
    for i = 1, shown do
      local it = sec.entries[i].item
      local t = it.file_type == "daily" and "Wednesday" or (it.title or "")
      if s.group == "project" then
        t = (it.type or it.file_type) .. " · " .. t
      end
      longest = math.max(longest, vim.fn.strdisplaywidth(t))
    end
  end
  local title_w = math.max(12, math.min(longest, 48, width - 2 - 10 - 2 - 30))
  local opts = {
    title_w = title_w,
    show_project = s.group == "type" and not s.project,
    show_type = s.group == "project",
    project_hl = project_hl,
  }
  local any = false
  for _, sec in ipairs(sections) do
    if #sec.entries > 0 then
      any = true
      add({})
      local folded = s.folded[sec.key]
      add({
        { (folded and "▸ " or "") .. "## " .. sec.label, "LogposeNotesHeading" },
        { (" (%d)"):format(#sec.entries), "LogposeNotesMeta" },
      }, { section = sec.key, heading = true })
      if not folded then
        add({})
        local shown = s.expanded[sec.key] and #sec.entries or math.min(#sec.entries, M.SHOWN)
        for i = 1, shown do
          add(row(sec.entries[i], opts), { file = sec.entries[i].item.file })
        end
        if shown < #sec.entries then
          add(
            { { ("  … %d more (<CR> to show all)"):format(#sec.entries - shown), "LogposeNotesHint" } },
            { section = sec.key, more = true }
          )
        end
      end
    end
  end
  if not any then
    add({})
    add({ { s.filter ~= "" and "  no notes match the filter" or "  no notes yet", "LogposeNotesHint" } })
  end
  add({})
  add({ { "<CR> open · e edit · / filter · p project/all · g group · ? help · q close", "LogposeNotesHint" } })
  return lines, rows
end

---@param s logpose.NotesState
---@param keep_file? string  put the cursor back on this note
local function render(s, keep_file)
  for name, link in pairs(M.HL) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  local win = vim.fn.bufwinid(s.buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local entries = M.collect(s.root, { project = s.project, filter = s.filter })
  local lines, rows = M.build(s, entries, width)
  s.rows = rows
  local texts = vim.tbl_map(function(chunks)
    local line = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, chunks))
    return (line:gsub("%s+$", ""))
  end, lines)
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, texts)
  vim.bo[s.buf].modifiable = false
  vim.bo[s.buf].modified = false
  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for i, chunks in ipairs(lines) do
    local col = 0
    for _, c in ipairs(chunks) do
      local end_col = math.min(col + #c[1], #texts[i])
      if c[2] and end_col > col then
        vim.api.nvim_buf_set_extmark(s.buf, ns, i - 1, col, { end_col = end_col, hl_group = c[2] })
      end
      col = col + #c[1]
    end
  end
  if keep_file and win ~= -1 then
    for i, r in pairs(rows) do
      if r.file == keep_file then
        pcall(vim.api.nvim_win_set_cursor, win, { i, 2 })
        break
      end
    end
  end
end

---@type table<integer, logpose.NotesState>
M.screens = {}

---@param s logpose.NotesState
---@return table?
local function at_cursor(s)
  return s.rows[vim.api.nvim_win_get_cursor(0)[1]]
end

--- The section the cursor is in (its heading or one of its rows).
---@param s logpose.NotesState
---@return string?
local function section_at(s)
  for i = vim.api.nvim_win_get_cursor(0)[1], 1, -1 do
    local r = s.rows[i]
    if r and r.section then
      return r.section
    end
  end
end

--- Open the notes screen in the current window. `opts.project` (default: the active project;
--- false for all) and `opts.filter` set what it shows.
---@param root string
---@param opts? { project?: string|false, filter?: string }
---@return integer buf
function M.open(root, opts)
  opts = opts or {}
  local name = "logpose://notes"
  local existing = vim.fn.bufnr(name)
  if existing > 0 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "logpose-notes"
  vim.api.nvim_win_set_buf(0, buf)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  local project = opts.project
  if project == nil then
    project = require("logpose.project").resolve(root)
  end
  ---@type logpose.NotesState
  local s = {
    root = root,
    buf = buf,
    project = project or nil,
    filter = opts.filter or "",
    group = "type",
    folded = {},
    expanded = {},
    rows = {},
  }
  M.screens[buf] = s
  render(s)
  -- start on the first note
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    if s.rows[i] and s.rows[i].file then
      vim.api.nvim_win_set_cursor(0, { i, 2 })
      break
    end
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local function current_file()
    local r = at_cursor(s)
    return r and r.file
  end
  map("<CR>", function()
    local r = at_cursor(s)
    if not r then
      return
    end
    if r.file then
      vim.cmd.edit(vim.fn.fnameescape(r.file))
    elseif r.more then
      s.expanded[r.section] = true
      render(s)
    elseif r.heading then
      s.folded[r.section] = not s.folded[r.section] or nil
      render(s)
    end
  end, "Open")
  map("z", function()
    local key = section_at(s)
    if key then
      s.folded[key] = not s.folded[key] or nil
      render(s)
      for i, r in pairs(s.rows) do
        if r.heading and r.section == key then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
        end
      end
    end
  end, "Fold the section")
  map("e", function()
    local file = current_file()
    if not file then
      return
    end
    require("logpose.edit").open(file, {
      root = root,
      on_save = function(path)
        render(s, path)
      end,
    })
  end, "Edit details")
  map("/", function()
    vim.ui.input(
      {
        prompt = "Filter notes: ",
        default = s.filter,
        completion = "customlist,v:lua.require'logpose.notes.browse'.complete_input",
      },
      ui.safely(function(input)
        if input == nil then
          return
        end
        s.filter = vim.trim(input)
        render(s, current_file())
      end)
    )
  end, "Filter")
  map("p", function()
    if s.project then
      s.project = nil
    else
      s.project = require("logpose.project").resolve(root)
      if not s.project then
        ui.notify("logpose: no active project here; showing all notes", vim.log.levels.INFO)
      end
    end
    render(s, current_file())
  end, "This project / all")
  map("g", function()
    s.group = s.group == "type" and "project" or "type"
    s.folded, s.expanded = {}, {}
    render(s, current_file())
  end, "Group by type / project")
  map("r", function()
    render(s, current_file())
  end, "Refresh")
  map("n", function()
    vim.cmd("Logpose note")
  end, "New topic note")
  map("d", function()
    vim.cmd("Logpose daily")
  end, "Daily note")
  map("b", function()
    vim.cmd("Logpose board")
  end, "Board")
  map("?", function()
    ui.notify(table.concat(M.HELP, "\n"), vim.log.levels.INFO)
  end, "Help")
  map("q", function()
    local alt = vim.fn.bufnr("#")
    if alt > 0 and alt ~= buf and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
      vim.cmd.buffer(alt)
    else
      vim.cmd.enew()
    end
  end, "Close")
  -- coming back (from a note you edited): show what changed
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      render(s, current_file())
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      M.screens[buf] = nil
    end,
  })
  return buf
end

--- Completion for the filter prompt ('customlist': the whole line, complete its last word).
---@param arglead string
---@param cmdline string
---@return string[]
function M.complete_input(arglead, cmdline, _)
  local line = cmdline or arglead
  local word = line:match("(%S*)$") or ""
  local before = line:sub(1, #line - #word)
  local out = {}
  for _, c in ipairs(require("logpose.search").complete(word, { "notes" })) do
    if vim.startswith(c, word) then
      table.insert(out, before .. c)
    end
  end
  return out
end

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    M.open(root, { filter = table.concat(opts.args, " ") })
  end))
end

---@param arglead string
function M.complete(arglead, _)
  return require("logpose.search").complete(arglead, { "notes" })
end

return M

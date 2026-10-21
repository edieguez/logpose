--- `:Logpose people [filter]`: everyone you work with, in one place. People with a page first
--- (name, role, how to reach them, when you last met, their open to-dos), then the people your
--- notes mention who have no page yet. `<Tab>` shows what involves someone, `<CR>` opens their
--- page, `e` edits it, `a` adds one, `m` starts a 1:1, `y`/`o` copy or open a way to reach them.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fit = require("logpose.board.text").fit
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.people")

M.HL = {
  LogposePeopleHeading = "Title",
  LogposePeopleName = "Normal",
  LogposePeopleRole = "Comment",
  LogposePeopleContact = "Identifier",
  LogposePeopleMeta = "Comment",
  LogposePeopleTodos = "DiagnosticWarn",
  LogposePeopleHint = "Comment",
}

M.HELP = {
  "logpose people",
  "  <CR>   open their page (no page yet: add one)",
  "  <Tab>  show / hide what involves them: meetings, open to-dos, tasks and notes",
  "  e      edit their details        a  add a person",
  "  m      start a 1:1 with them",
  "  y      copy a way to reach them  o  open it (mail, chat…)",
  "  /      filter (any part of a name, role, project)",
  "  R      rename them everywhere",
  "  p      this project / everyone   r  refresh",
  "  q      close                     ?  this help",
}

--- What involves each person (by slug): meetings (newest first), open to-dos, other mentions.
---@param root string
---@param people logpose.Person[]
---@return table<logpose.Person, { meetings: logpose.Item[], todos: logpose.Item[], mentions: logpose.Item[], last?: string }>
function M.involvement(root, people)
  local by_slug = {}
  for _, p in ipairs(people) do
    for s in pairs(p.slugs) do
      by_slug[s] = by_slug[s] or p
    end
  end
  local out = {}
  for _, p in ipairs(people) do
    out[p] = { meetings = {}, todos = {}, mentions = {} }
  end
  for _, it in ipairs(require("logpose.index").build(root)) do
    local seen = {}
    for _, slug in ipairs(it.people or {}) do
      local p = by_slug[slug]
      if p and not seen[p] then
        seen[p] = true
        local inv = out[p]
        if it.kind == "note" and it.file_type == "meeting" then
          table.insert(inv.meetings, it)
          if it.date and (not inv.last or it.date > inv.last) then
            inv.last = it.date
          end
        elseif it.kind == "todo" and not it.checked then
          table.insert(inv.todos, it)
        elseif it.kind ~= "person" and it.kind ~= "todo" then
          table.insert(inv.mentions, it)
        end
      end
    end
  end
  for _, inv in pairs(out) do
    table.sort(inv.meetings, function(a, b)
      return (a.date or "") > (b.date or "")
    end)
  end
  return out
end

---@class logpose.PeopleState
---@field root string
---@field buf integer
---@field project? string
---@field filter string
---@field expanded table<string, boolean>
---@field rows table<integer, { person?: logpose.Person, file?: string, lnum?: integer }>

--- The screen's lines (chunks) and what each row is.
---@param s logpose.PeopleState
---@param width integer
---@return table[], table<integer, table>
function M.build(s, width)
  local people = require("logpose.people")
  local known = people.known(s.root)
  local inv = M.involvement(s.root, known)
  local list = known
  if s.filter ~= "" then
    list = people.match(known, s.filter, s.project)
    -- also by role and project
    local q = people.plain(s.filter)
    for _, p in ipairs(known) do
      local extra = (p.role and people.plain(p.role):find(q, 1, true)) or p.projects[q]
      if extra and not vim.tbl_contains(list, p) then
        table.insert(list, p)
      end
    end
  end
  if s.project then
    list = vim.tbl_filter(function(p)
      return (p.projects[s.project] or 0) > 0
    end, list)
  end
  local paged, seen = {}, {}
  for _, p in ipairs(list) do
    table.insert(p.page and paged or seen, p)
  end
  table.sort(paged, function(a, b)
    local la, lb = inv[a].last or "", inv[b].last or ""
    if la ~= lb then
      return la > lb -- met most recently first
    end
    return people.plain(a.name) < people.plain(b.name)
  end)

  local lines, rows = {}, {}
  local function add(chunks, r)
    table.insert(lines, chunks)
    rows[#lines] = r
  end
  local scope = s.project and require("logpose.project").title(s.root, s.project) or "everyone"
  add({ { "# People · " .. scope, "LogposePeopleHeading" } })
  if s.filter ~= "" then
    add({ { "filter: " .. s.filter, "LogposePeopleHint" } })
  end
  local name_w = 12
  for _, p in ipairs(list) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(p.name))
  end
  name_w = math.min(name_w, 28)
  local role_w = 0
  for _, p in ipairs(paged) do
    role_w = math.max(role_w, vim.fn.strdisplaywidth(p.role or ""))
  end
  role_w = math.min(role_w, 22)
  local today = date.today()

  local function person_row(p)
    local i = inv[p]
    local chunks = { { "  " }, { fit(p.name, name_w), "LogposePeopleName" } }
    if role_w > 0 then
      table.insert(chunks, { "  " })
      table.insert(chunks, { fit(p.role or "", role_w), "LogposePeopleRole" })
    end
    local meta = {}
    local reach = vim.tbl_map(function(c)
      return c.shown
    end, people.contacts_of(p))
    if #reach > 0 then
      table.insert(meta, { table.concat(reach, " · "), "LogposePeopleContact" })
    end
    if i.last then
      table.insert(meta, { "met " .. date.relative(i.last, today), "LogposePeopleMeta" })
    end
    if #i.todos > 0 then
      table.insert(meta, { ("☐ %d open"):format(#i.todos), "LogposePeopleTodos" })
    end
    if not p.page then
      table.insert(meta, { ("%d mention%s"):format(p.count, p.count == 1 and "" or "s"), "LogposePeopleMeta" })
    end
    if not s.project then
      local projects = {}
      for name, n in pairs(p.projects) do
        if n > 0 then
          table.insert(projects, name)
        end
      end
      table.sort(projects)
      if #projects > 0 then
        table.insert(meta, { "◆ " .. table.concat(projects, ", "), "LogposePeopleMeta" })
      end
    end
    for k, m in ipairs(meta) do
      table.insert(chunks, { k == 1 and "  " or "  ·  ", "LogposePeopleMeta" })
      table.insert(chunks, m)
    end
    add(chunks, { person = p })
    if s.expanded[p.slug] then
      local function detail(sym, it, label)
        add({ { "      " .. sym .. " ", "LogposePeopleMeta" }, { label } }, { file = it.file, lnum = it.lnum })
      end
      for k = 1, math.min(5, #i.meetings) do
        local it = i.meetings[k]
        detail("◷", it, ("%s  %s"):format(it.date and date.short(it.date, today) or "", it.title or ""))
      end
      for k = 1, math.min(5, #i.todos) do
        local it = i.todos[k]
        detail("☐", it, ("%s  · %s"):format(it.text, it.title or vim.fs.basename(it.file)))
      end
      for k = 1, math.min(5, #i.mentions) do
        local it = i.mentions[k]
        detail(it.kind == "task" and "▣" or "✎", it, it.title or it.text)
      end
      if #i.meetings + #i.todos + #i.mentions == 0 then
        add({ { "      nothing mentions them yet", "LogposePeopleHint" } }, {})
      end
    end
  end

  if #paged > 0 then
    add({})
    add({ { ("## With a page (%d)"):format(#paged), "LogposePeopleHeading" } })
    add({})
    for _, p in ipairs(paged) do
      person_row(p)
    end
  end
  if #seen > 0 then
    add({})
    add({ { ("## In your notes, no page yet (%d)"):format(#seen), "LogposePeopleHeading" } })
    add({})
    for _, p in ipairs(seen) do
      person_row(p)
    end
  end
  if #paged + #seen == 0 then
    add({})
    add({
      { s.filter ~= "" and "  nobody matches the filter" or "  nobody yet: a adds a person", "LogposePeopleHint" },
    })
  end
  add({})
  add({ { "<CR> page · <Tab> details · e edit · a add · m 1:1 · y/o contact · ? help", "LogposePeopleHint" } })
  return lines, rows
end

---@param s logpose.PeopleState
---@param keep? string  slug to keep the cursor on
local function render(s, keep)
  for name, link in pairs(M.HL) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  local win = vim.fn.bufwinid(s.buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local lines, rows = M.build(s, width)
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
  if keep and win ~= -1 then
    for i, r in pairs(rows) do
      if r.person and r.person.slug == keep then
        pcall(vim.api.nvim_win_set_cursor, win, { i, 2 })
        break
      end
    end
  end
end

---@type table<integer, logpose.PeopleState>
M.screens = {}

--- The person on the cursor's row, or the one whose details it's in.
---@param s logpose.PeopleState
---@return logpose.Person?
local function person_at(s)
  for i = vim.api.nvim_win_get_cursor(0)[1], 1, -1 do
    local r = s.rows[i]
    if not r or (not r.person and not r.file and next(r) == nil and i ~= vim.api.nvim_win_get_cursor(0)[1]) then
      return nil
    end
    if r.person then
      return r.person
    end
  end
end

--- Add or edit a person: the form, then back to the screen.
---@param s logpose.PeopleState
---@param p? logpose.Person
local function edit(s, p)
  local edit_mod = require("logpose.edit")
  local function back(path)
    if vim.api.nvim_buf_is_valid(s.buf) then
      render(s, path and vim.fn.fnamemodify(path, ":t:r") or (p and p.slug))
    end
  end
  if p and p.page then
    edit_mod.open(p.page, { root = s.root, on_save = back })
  else
    edit_mod.open_new_note(s.root, "person", {
      name = p and p.name,
      project = s.project,
    }, { on_save = back })
  end
end

--- Pick one of a person's ways to reach them (directly when there's one).
---@param p logpose.Person
---@param want_url boolean
---@param fn fun(c: table)
local function with_contact(p, want_url, fn)
  local list = require("logpose.people").contacts_of(p)
  if want_url then
    list = vim.tbl_filter(function(c)
      return c.url ~= nil
    end, list)
  end
  if #list == 0 then
    ui.notify(
      ("logpose: no way to %s %s yet (e adds one)"):format(want_url and "open for" or "reach", p.name),
      vim.log.levels.INFO
    )
    return
  end
  if #list == 1 then
    return fn(list[1])
  end
  vim.ui.select(
    list,
    {
      prompt = p.name,
      format_item = function(c)
        return ("%s: %s"):format(c.label, c.shown)
      end,
    },
    ui.safely(function(c)
      if c then
        fn(c)
      end
    end)
  )
end

--- Open the people screen in the current window.
---@param root string
---@param opts? { project?: string|false, filter?: string }
---@return integer buf
function M.open(root, opts)
  opts = opts or {}
  local name = "logpose://people"
  local existing = vim.fn.bufnr(name)
  if existing > 0 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "logpose-people"
  vim.api.nvim_win_set_buf(0, buf)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  local project = opts.project
  if project == nil then
    project = require("logpose.project").resolve(root)
  end
  ---@type logpose.PeopleState
  local s = { root = root, buf = buf, project = project or nil, filter = opts.filter or "", expanded = {}, rows = {} }
  M.screens[buf] = s
  render(s)
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    if s.rows[i] and s.rows[i].person then
      vim.api.nvim_win_set_cursor(0, { i, 2 })
      break
    end
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", function()
    local r = s.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if r and r.file then
      vim.cmd.edit(vim.fn.fnameescape(r.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { r.lnum or 1, 0 })
    elseif r and r.person then
      if r.person.page then
        vim.cmd.edit(vim.fn.fnameescape(r.person.page))
      else
        edit(s, r.person)
      end
    end
  end, "Open their page")
  map("<Tab>", function()
    local p = person_at(s)
    if p then
      s.expanded[p.slug] = not s.expanded[p.slug] or nil
      render(s, p.slug)
    end
  end, "Details")
  map("e", function()
    local p = person_at(s)
    if p then
      edit(s, p)
    end
  end, "Edit")
  map("a", function()
    local p = person_at(s)
    edit(s, p and not p.page and p or nil) -- on someone without a page: theirs
  end, "Add a person")
  map("m", function()
    local p = person_at(s)
    if not p then
      return
    end
    local key
    for _, t in ipairs(require("logpose.notes.meeting").types()) do
      if t.spec.person then
        key = key or t.key
      end
    end
    require("logpose.edit").open_new_note(root, "meeting", { type = key, title = p.name, project = s.project })
  end, "Start a 1:1")
  map("y", function()
    local p = person_at(s)
    if p then
      with_contact(p, false, function(c)
        vim.fn.setreg('"', c.value)
        pcall(vim.fn.setreg, "+", c.value)
        ui.notify(("logpose: copied %s's %s: %s"):format(p.name, c.label, c.value), vim.log.levels.INFO)
      end)
    end
  end, "Copy a way to reach them")
  map("o", function()
    local p = person_at(s)
    if p then
      with_contact(p, true, function(c)
        vim.ui.open(c.url)
      end)
    end
  end, "Open a way to reach them")
  map("R", function()
    local p = person_at(s)
    if not p then
      return
    end
    vim.ui.input(
      { prompt = ("New name for %s: "):format(p.name), default = p.name },
      ui.safely(function(input)
        if input and vim.trim(input) ~= "" and vim.trim(input) ~= p.name then
          require("logpose.people.rename").rename(p.slug, input, {
            after = function()
              if vim.api.nvim_buf_is_valid(buf) then
                render(s, require("logpose.util.text").slugify(input))
              end
            end,
          })
        end
      end)
    )
  end, "Rename")
  map("/", function()
    vim.ui.input(
      { prompt = "Filter people: ", default = s.filter },
      ui.safely(function(input)
        if input ~= nil then
          s.filter = vim.trim(input)
          render(s)
        end
      end)
    )
  end, "Filter")
  map("p", function()
    if s.project then
      s.project = nil
    else
      s.project = require("logpose.project").resolve(root)
      if not s.project then
        ui.notify("logpose: no active project here; showing everyone", vim.log.levels.INFO)
      end
    end
    local p = person_at(s)
    render(s, p and p.slug)
  end, "This project / everyone")
  map("r", function()
    local p = person_at(s)
    render(s, p and p.slug)
  end, "Refresh")
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
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      local p = person_at(s)
      render(s, p and p.slug)
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

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    M.open(root, { filter = table.concat(opts.args, " "), project = #opts.args > 0 and false or nil })
  end))
end

--- `:Logpose person [name]`: open their page; without a page (or a name), the form to add one.
---@param opts logpose.CommandOpts
function M.person_command(opts)
  local name = vim.trim(table.concat(opts.args, " "))
  config.with_root(ui.safely(function(root)
    local people = require("logpose.people")
    local p = name ~= "" and people.find(people.known(root), name) or nil
    if p and p.page then
      vim.cmd.edit(vim.fn.fnameescape(p.page))
      return
    end
    require("logpose.edit").open_new_note(root, "person", {
      name = p and p.name or (name ~= "" and name or nil),
      project = require("logpose.project").resolve(root),
    })
  end))
end

--- Completion: handles (`ana-lopez`), which the command line takes as one word.
---@param arglead string
function M.complete_person(arglead, _)
  local people = require("logpose.people")
  return vim.tbl_map(function(p)
    return p.slug
  end, people.match(people.known(), arglead))
end

return M

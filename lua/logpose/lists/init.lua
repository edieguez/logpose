--- The lists: meetings, notes and people as lists grouped under headings, with the board's
--- ways: `/` filters (the find language: and, or, not, any frontmatter field), `g` changes the
--- grouping, `s` the order, `p` this project / all, `<Tab>` shows what's in an entry, `K` peeks.
--- Moving an entry to another group (`m`, `<`, `>`) changes the note, so the list and the files
--- always agree (another project moves a meeting to that project's folder, another tag swaps the
--- tag…). Groupings worked out from a note (its week, month, last meeting) can't be moved to.
---
--- A view (`lists/meetings.lua`, `lists/notes.lua`, `lists/people.lua`) says what's listed:
---   name, title, filetype, help: what and how it's called
---   collect(s): the entries, each { key, item (for filters), file? … }
---   groupings: { key, label, of(e, s) -> { {key, label, order?}… }, move?(s, e, from, to) -> key?,
---                targets?(s) -> { {key, label}… }, ask?: string (prompt for a new group),
---                descending?: boolean, none?: string }
---   sorts: { label, cmp(a, b) }
---   columns: { {key, max?, min?, flex?, hl?}… }; cells(e, ctx) -> { [key] = string | chunks }
---     (a table across the window: each column as wide as its longest cell; `flex` columns take
---     the room left over, and give way first when it's narrow)
---   or row(e, ctx) -> chunks;  details?(e, s) -> { { chunks, file?, lnum? }… }
---   open(e, s), edit(e, s, done(key?)), add(s, group, done(key?)), keys(s, map, helpers)
local config = require("logpose.config")
local text = require("logpose.board.text")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.lists")

M.HL = {
  LogposeListTitle = "Title",
  LogposeListScope = "Title",
  LogposeListFilter = "Special",
  LogposeListGroup = "Title",
  LogposeListCount = "Comment",
  LogposeListTree = "NonText",
  LogposeListDate = "Comment",
  LogposeListMeta = "Comment",
  LogposeListTodos = "DiagnosticWarn",
  LogposeListTasks = "Directory",
  LogposeListPeople = "Identifier",
  LogposeListHint = "Comment",
}

---@class logpose.ListEntry
---@field key string        unique in the list (a file, a person's slug)
---@field item logpose.Item what filters look at
---@field file? string      what <CR> opens

---@class logpose.ListState
---@field root string
---@field buf integer
---@field view table
---@field project? string
---@field filter string
---@field group integer     index in view.groupings
---@field sort integer      index in view.sorts
---@field folded table<string, boolean>
---@field expanded table<string, boolean>
---@field rows table<integer, table>
---@field groups { key: string, label: string }[]  as shown, in order

---@param s logpose.ListState
---@return table
local function grouping(s)
  return s.view.groupings[s.group]
end

--- Entries matching the state's project and filter.
---@param s logpose.ListState
---@return logpose.ListEntry[]
function M.entries(s)
  local query = require("logpose.query")
  local q = query.parse(query.split(s.filter), nil, true)
  local out = {}
  for _, e in ipairs(s.view.collect(s)) do
    local it = e.item
    local in_scope = not s.project
      or it.project == s.project
      or vim.tbl_contains(it.tags or {}, s.project)
      or (e.projects and e.projects[s.project])
    if in_scope and query.match(it, q) then
      table.insert(out, e)
    end
  end
  table.sort(out, s.view.sorts[s.sort].cmp)
  return out
end

--- Entries under their groups, groups in order.
---@param s logpose.ListState
---@param entries logpose.ListEntry[]
---@return { key: string, label: string, entries: logpose.ListEntry[] }[]
function M.groups(s, entries)
  local g = grouping(s)
  local list, by_key = {}, {}
  for _, e in ipairs(entries) do
    local keys = g.of(e, s)
    if #keys == 0 then
      keys = { { key = "", label = g.none or "None" } }
    end
    for _, k in ipairs(keys) do
      local grp = by_key[k.key]
      if not grp then
        grp = { key = k.key, label = k.label, order = k.order, entries = {} }
        by_key[k.key] = grp
        table.insert(list, grp)
      end
      table.insert(grp.entries, e)
    end
  end
  table.sort(list, function(a, b)
    if (a.key == "") ~= (b.key == "") then
      return b.key == "" -- "none" last
    end
    local oa, ob = a.order or 0, b.order or 0
    if oa ~= ob then
      return oa < ob
    end
    if g.descending then
      return a.key > b.key
    end
    return a.label:lower() < b.label:lower()
  end)
  return list
end

--- The screen as lines of chunks, and what each row is.
local GAP = 3

local function cell_chunks(col, v)
  if v == nil or v == "" then
    return {}
  end
  if type(v) == "string" then
    return { { v, col.hl } }
  end
  return v
end

local function chunks_width(chunks)
  local w = 0
  for _, c in ipairs(chunks) do
    w = w + vim.fn.strdisplaywidth(c[1])
  end
  return w
end

--- How wide each column is in a table `avail` cells wide: as wide as the longest cell (up to its
--- `max`); room left over goes to the `flex` columns (the title), so the rest sit at the right
--- edge; short of room, `flex` columns shrink (to their `min`), then columns go from the right.
---@param columns table[]
---@param cells table<string, table>[]  each entry's cells, as chunks
---@param avail integer
---@return { col: table, width: integer, gap: integer }[]
function M.widths(columns, cells, avail)
  local cols = {}
  for _, col in ipairs(columns) do
    local w = 0
    for _, c in ipairs(cells) do
      w = math.max(w, chunks_width(c[col.key] or {}))
    end
    w = math.min(w, col.max or 60)
    if w > 0 then
      table.insert(cols, { col = col, width = w, gap = GAP })
    end
  end
  local function total()
    local t = 0
    for i, c in ipairs(cols) do
      t = t + c.width + (i > 1 and GAP or 0)
    end
    return t
  end
  local function shrink(floor)
    for _, c in ipairs(cols) do
      local over = total() - avail
      if over <= 0 then
        return
      end
      if c.col.flex then
        c.width = math.max(math.min(c.width, floor or c.col.min or 12), c.width - over)
      end
    end
  end
  shrink()
  while total() > avail and #cols > 1 and not cols[#cols].col.flex do
    table.remove(cols)
  end
  shrink(6)
  if #cols > 0 then
    cols[1].gap = 0
  end
  local extra = avail - total()
  if extra > 0 and #cols > 1 then
    -- room to spare: the flex columns take it, so the rest of the row sits at the right edge
    local flex = vim.tbl_filter(function(c)
      return c.col.flex
    end, cols)
    if #flex == 0 then
      flex = { cols[1] }
    end
    local each, rest = math.floor(extra / #flex), extra % #flex
    for i, c in ipairs(flex) do
      c.width = c.width + each + (i <= rest and 1 or 0)
    end
  end
  return cols
end

--- The screen as lines of chunks, and what each row is.
---@param s logpose.ListState
---@param width integer
---@return table[], table<integer, table>
function M.build(s, width)
  local project = require("logpose.project")
  local entries = M.entries(s)
  local groups = M.groups(s, entries)
  s.groups = vim.tbl_map(function(g)
    return { key = g.key, label = g.label }
  end, groups)
  local lines, rows = {}, {}
  -- on a wide window the list keeps to `lists.max_width`, in the middle
  local max_w = config.get().lists.max_width or 160
  local inner = math.max(20, math.min(width - 1, max_w))
  local margin = width - 1 > max_w and math.floor((width - inner) / 2) or 0
  s.margin = margin
  local function add(chunks, r)
    if margin > 0 and #chunks > 0 then
      table.insert(chunks, 1, { string.rep(" ", margin) })
    end
    table.insert(lines, chunks)
    rows[#lines] = r
  end
  local g, sort = grouping(s), s.view.sorts[s.sort]
  s.count = #entries
  -- the window's top bar: what this is, then how it's shown
  local scope = s.project and project.title(s.root, s.project) or "all projects"
  local function esc(str)
    return (str:gsub("%%", "%%%%"))
  end
  local noun = #entries == 1 and (s.view.one or s.view.name) or (s.view.noun or s.view.name)
  s.winbar = "%#LogposeListTitle# "
    .. esc(s.view.title)
    .. "%#LogposeListScope# · "
    .. esc(scope)
    .. (s.filter ~= "" and ("%#LogposeListFilter#  " .. esc(s.filter)) or "")
    .. "%=%#LogposeListHint#"
    .. esc(("%d %s · by %s · %s · ? help "):format(#entries, noun, g.label, sort.label))
  -- `group`: rows leave out what their heading already says (the project, the type)
  local ctx = { s = s, width = width, all_projects = not s.project, group = g.key, entries = entries, project_hl = {} }
  local pages = project.pages(s.root)
  ctx.hl = function(name)
    ctx.project_hl[name] = ctx.project_hl[name] or project.hl(s.root, name, pages) or "LogposeBoardProject"
    return ctx.project_hl[name]
  end
  if s.view.layout then
    s.view.layout(ctx)
  end
  -- a table: every entry's cells first, so the columns line up across the groups
  local cols, cells = nil, {}
  if s.view.columns then
    local all = {}
    for _, e in ipairs(entries) do
      local raw = s.view.cells(e, ctx)
      local c = {}
      for _, col in ipairs(s.view.columns) do
        c[col.key] = cell_chunks(col, raw[col.key])
      end
      cells[e.key] = c
      table.insert(all, c)
    end
    cols = M.widths(s.view.columns, all, inner - 2 - 1)
  end
  local function row_of(e)
    if not cols then
      return s.view.row(e, ctx)
    end
    local out = {}
    for _, c in ipairs(cols) do
      if c.gap > 0 then
        table.insert(out, { string.rep(" ", c.gap) })
      end
      vim.list_extend(out, text.fit_chunks(cells[e.key][c.col.key], c.width))
    end
    return out
  end
  local band = config.get().lists.bands ~= false and require("logpose.util.screen").band_hl() or nil
  for gi, grp in ipairs(groups) do
    if gi > 1 then
      add({})
    end
    local folded = s.folded[grp.key]
    add({
      { (folded and "▸ " or "▾ ") .. grp.label, "LogposeListGroup" },
      { ("  %d"):format(#grp.entries), "LogposeListCount" },
    }, { heading = true, group = grp.key })
    if not folded then
      for ei, e in ipairs(grp.entries) do
        local chunks = row_of(e)
        table.insert(chunks, 1, { "  " })
        add(chunks, { entry = e, group = grp.key })
        if band and ei % 2 == 0 then
          -- every other row banded, so a row is easy to follow across a wide window
          chunks.band = { hl = band, from = margin, width = margin + inner }
        end
        if s.expanded[e.key] and s.view.details then
          local details = s.view.details(e, s)
          if #details == 0 then
            details = { { chunks = { { "nothing more to show", "LogposeListHint" } } } }
          end
          for di, d in ipairs(details) do
            local c = vim.deepcopy(d.chunks)
            table.insert(c, 1, { di == #details and "    └ " or "    ├ ", "LogposeListTree" })
            add(c, { entry = e, group = grp.key, file = d.file, lnum = d.lnum, detail = true })
          end
        end
      end
    end
  end
  if #groups == 0 then
    if s.filter ~= "" then
      add({ { ("  No %s match ‹%s›"):format(s.view.noun or s.view.name, s.filter), "LogposeListHint" } })
      add({ { "  / changes the filter · <BS> clears it · ? lists what you can filter by", "LogposeListHint" } })
    else
      add({ { "  " .. (s.view.empty or "Nothing yet"), "LogposeListHint" } })
    end
  end
  add({})
  add({
    { s.view.footer or "<CR> open · <Tab> details · / filter · g group · m move · ? help", "LogposeListHint" },
  })
  return lines, rows
end

---@param s logpose.ListState
---@param keep? string  an entry key to keep the cursor on
function M.render(s, keep)
  if not vim.api.nvim_buf_is_valid(s.buf) then
    return
  end
  local screen = require("logpose.util.screen")
  screen.links(M.HL)
  local win = vim.fn.bufwinid(s.buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local lines, rows = M.build(s, width)
  s.rows = rows
  if win ~= -1 then
    vim.wo[win].winbar = s.winbar
  end
  local texts = screen.draw(s.buf, ns, lines)
  if keep and win ~= -1 then
    for i = 1, #texts do
      local r = rows[i]
      if r and r.entry and not r.detail and r.entry.key == keep then
        pcall(vim.api.nvim_win_set_cursor, win, { i, (s.margin or 0) + 2 })
        return
      end
    end
  end
end

---@type table<integer, logpose.ListState>
M.screens = {}

---@param s logpose.ListState
---@return table?
local function at_cursor(s)
  return s.rows[vim.api.nvim_win_get_cursor(0)[1]]
end

--- The entry on the cursor's row (or the one its detail line belongs to) and its group.
---@param s logpose.ListState
---@return logpose.ListEntry?, string?
function M.entry_at(s)
  local r = at_cursor(s)
  if r and r.entry then
    return r.entry, r.group
  end
  return nil, r and r.group
end

--- The group the cursor is in.
---@param s logpose.ListState
---@return string?
local function group_at(s)
  for i = vim.api.nvim_win_get_cursor(0)[1], 1, -1 do
    local r = s.rows[i]
    if r and r.group then
      return r.group
    end
  end
end

--- Move `e` from group `from` to group `to` (changing its note), then show it there.
---@param s logpose.ListState
---@param e logpose.ListEntry
---@param from string
---@param to string
function M.move(s, e, from, to)
  local g = grouping(s)
  if from == to then
    return
  end
  local key = g.move(s, e, from, to)
  require("logpose.index").clear_cache()
  M.render(s, key or e.key)
end

--- Where `e` can go: the view's targets, or the groups shown; then a new one if it asks for it.
---@param s logpose.ListState
---@param from string
---@return { key: string, label: string }[]
local function targets(s, from)
  local g = grouping(s)
  local list = g.targets and g.targets(s) or vim.deepcopy(s.groups)
  return vim.tbl_filter(function(t)
    return t.key ~= from
  end, list)
end

--- Why entries can't be moved in this grouping (nil when they can).
---@param s logpose.ListState
---@return string?
local function fixed(s)
  local g = grouping(s)
  if not g.move then
    return ("logpose: grouped by %s, which comes from the note itself (e edits it)"):format(g.label)
  end
end

--- Open a list in the current window.
---@param root string
---@param view table
---@param opts? { project?: string|false, filter?: string, group?: string }
---@return integer buf
function M.open(root, view, opts)
  opts = opts or {}
  local buf = ui.screen_buf("logpose://" .. view.name, view.filetype or ("logpose-" .. view.name))
  local win = ui.show(buf)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  local project = opts.project
  if project == nil then
    project = require("logpose.project").resolve(root)
  end
  local group = 1
  for i, g in ipairs(view.groupings) do
    if g.key == opts.group then
      group = i
    end
  end
  ---@type logpose.ListState
  local s = {
    root = root,
    buf = buf,
    view = view,
    project = project or nil,
    filter = opts.filter or "",
    group = group,
    sort = 1,
    folded = {},
    expanded = {},
    rows = {},
    groups = {},
  }
  M.screens[buf] = s
  M.render(s)
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    if s.rows[i] and s.rows[i].entry then
      vim.api.nvim_win_set_cursor(0, { i, (s.margin or 0) + 2 })
      break
    end
  end

  local map = ui.mapper(buf)
  local function keep()
    local e = M.entry_at(s)
    return e and e.key
  end
  local function refresh(key)
    M.render(s, key or keep())
  end

  map("<CR>", function()
    local r = at_cursor(s)
    if not r then
      return
    end
    if r.detail and r.file then
      vim.cmd.edit(vim.fn.fnameescape(r.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { r.lnum or 1, 0 })
    elseif r.entry then
      view.open(r.entry, s)
    elseif r.heading then
      s.folded[r.group] = not s.folded[r.group] or nil
      refresh()
    end
  end, "Open")
  map("<Tab>", function()
    local e = M.entry_at(s)
    if e then
      s.expanded[e.key] = not s.expanded[e.key] or nil
      refresh(e.key)
    end
  end, "Details")
  map("K", function()
    local e = M.entry_at(s)
    if e and e.file then
      require("logpose.util.peek").open(e.file, e.item.title or e.item.text, function()
        refresh(e.key)
      end)
    end
  end, "Peek")
  map("z", function()
    local key = group_at(s)
    if key then
      s.folded[key] = not s.folded[key] or nil
      refresh()
      for i, r in pairs(s.rows) do
        if r.heading and r.group == key then
          vim.api.nvim_win_set_cursor(0, { i, s.margin or 0 })
        end
      end
    end
  end, "Fold the group")
  local function jump(dir)
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local last = vim.api.nvim_buf_line_count(buf)
    local i = cur + dir
    while i >= 1 and i <= last do
      if s.rows[i] and s.rows[i].heading then
        vim.api.nvim_win_set_cursor(0, { i, s.margin or 0 })
        return
      end
      i = i + dir
    end
  end
  map("]]", function()
    jump(1)
  end, "Next group")
  map("[[", function()
    jump(-1)
  end, "Previous group")
  map("/", function()
    M.filter_bar(s)
  end, "Filter")
  map("<BS>", function()
    if s.filter ~= "" then
      s.filter = ""
      refresh()
    end
  end, "Clear the filter")
  map("g", function()
    s.group = s.group % #view.groupings + 1
    s.folded = {}
    refresh()
    ui.notify(("logpose: grouped by %s"):format(grouping(s).label), vim.log.levels.INFO)
  end, "Change the grouping")
  map("s", function()
    s.sort = s.sort % #view.sorts + 1
    refresh()
  end, "Change the order")
  map("p", function()
    if s.project then
      s.project = nil
    else
      s.project = require("logpose.project").resolve(root)
      if not s.project then
        ui.notify("logpose: no active project; showing all of them", vim.log.levels.INFO)
      end
    end
    refresh()
  end, "This project / all")
  map("m", function()
    local e, from = M.entry_at(s)
    if not e then
      return
    end
    local why = fixed(s)
    if why then
      return ui.notify(why, vim.log.levels.INFO)
    end
    local g = grouping(s)
    local list = targets(s, from)
    if g.ask then
      table.insert(list, { key = "\0new", label = "new…" })
    end
    vim.ui.select(
      list,
      {
        prompt = ("Move %s to"):format(e.item.title or e.item.text),
        format_item = function(t)
          return t.label
        end,
      },
      ui.safely(function(t)
        if not t then
          return
        end
        if t.key ~= "\0new" then
          return M.move(s, e, from, t.key)
        end
        vim.ui.input(
          { prompt = g.ask },
          ui.safely(function(value)
            value = value and vim.trim(value)
            if value and value ~= "" then
              M.move(s, e, from, value)
            end
          end)
        )
      end)
    )
  end, "Move to another group")
  local function step(dir)
    local e, from = M.entry_at(s)
    if not e then
      return
    end
    local why = fixed(s)
    if why then
      return ui.notify(why, vim.log.levels.INFO)
    end
    for i, grp in ipairs(s.groups) do
      if grp.key == from then
        -- a count moves that many groups (3>), stopping at the last one
        local j = math.max(1, math.min(#s.groups, i + dir * vim.v.count1))
        local to = j ~= i and s.groups[j]
        if to then
          M.move(s, e, from, to.key)
        end
        return
      end
    end
  end
  map(">", function()
    step(1)
  end, "Move to the next group")
  map("<", function()
    step(-1)
  end, "Move to the previous group")
  map("e", function()
    local e = M.entry_at(s)
    if e and view.edit then
      view.edit(e, s, function(key)
        refresh(key or e.key)
      end)
    end
  end, "Edit")
  map("a", function()
    if view.add then
      local _, grp = M.entry_at(s)
      view.add(s, grp or group_at(s), function(key)
        refresh(key)
      end)
    end
  end, "Add")
  map("r", function()
    refresh()
  end, "Refresh")
  map("?", function()
    require("logpose.util.help").with_filters(view.title, M.help(view))
  end, "Help")
  map("q", function()
    require("logpose.util.screen").leave(buf)
  end, "Close")
  if view.keys then
    view.keys(s, map, { refresh = refresh, entry_at = M.entry_at })
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      refresh()
    end,
  })
  -- the window's width changed: lay the rows out again
  local width_was = vim.api.nvim_win_get_width(win)
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = vim.api.nvim_create_augroup("logpose.lists.resize." .. buf, { clear = true }),
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return true
      end
      local w = vim.fn.bufwinid(buf)
      if w ~= -1 and vim.api.nvim_win_get_width(w) ~= width_was then
        width_was = vim.api.nvim_win_get_width(w)
        M.render(s) -- same lines, laid out again: the cursor stays put
      end
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

--- The filter bar over the list: the list follows as you type; <Esc> puts the old filter back.
---@param s logpose.ListState
function M.filter_bar(s)
  local win = vim.fn.bufwinid(s.buf)
  if win == -1 then
    return
  end
  local before = s.filter
  local e = M.entry_at(s)
  local noun = s.view.noun or s.view.name
  require("logpose.filter.bar").open({
    win = win,
    title = "Filter " .. noun,
    text = s.filter,
    root = s.root,
    on_change = function(text)
      s.filter = vim.trim(text)
      M.render(s, e and e.key)
      return ("%d %s"):format(s.count or 0, s.count == 1 and (s.view.one or noun) or noun)
    end,
    on_done = function(text)
      s.filter = text or before
      M.render(s, e and e.key)
    end,
  })
end

--- The help rows: the view's own keys, then the shared ones.
---@param view table
---@return table[]
function M.help(view)
  local rows = { { "Keys" } }
  vim.list_extend(rows, view.help or {})
  local function labels(list)
    return table.concat(
      vim.tbl_map(function(x)
        return x.label
      end, list),
      " · "
    )
  end
  vim.list_extend(rows, {
    { "<CR>", "open (a heading: fold the group; a detail: open it)" },
    { "<Tab>", "details" },
    { "K", "peek: read and edit in a floating window" },
    { "/", "filter: the list follows as you type; Tab completes" },
    { "<BS>", "clear the filter" },
    { "g", "group by: " .. labels(view.groupings) },
    { "s", "order: " .. labels(view.sorts) },
    { "m", "move to another group: changes the note" },
    { "< >", "move to the previous / next group (3> three groups on)" },
    { "e", "edit" },
    { "a", "add one, in the group you're in" },
    { "p", "this project / all projects" },
    { "z", "fold the group" },
    { "]] [[", "next / previous group" },
    { "r  q", "refresh · close" },
  })
  return rows
end

--- `:Logpose <view> [filter]` for a view module.
---@param view table
---@return fun(opts: logpose.CommandOpts)
function M.command_for(view)
  return function(opts)
    config.with_root(ui.safely(function(root)
      -- a search from the command line looks in every project
      M.open(root, view, { filter = table.concat(opts.args, " "), project = #opts.args > 0 and false or nil })
    end))
  end
end

return M

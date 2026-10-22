--- `:Logpose people [filter]`: everyone you work with. People with a page and the people your
--- notes mention who have none yet, grouped by page, project, role or when you last met. Moving
--- someone to another project or role changes their page. `y`/`o` copy or open a way to reach
--- them, `1` starts a 1:1, `R` renames them everywhere.
local common = require("logpose.lists.common")
local config = require("logpose.config")
local lists = require("logpose.lists")
local ui = require("logpose.util.ui")

local M = {}

M.name = "people"
M.title = "People"
M.empty = "Nobody yet: a adds a person"
M.footer = "<CR> page · <Tab> details · e edit · a add · 1 1:1 · y/o contact · / filter · ? help"
M.noun = "people"
M.one = "person"
M.help = {
  { "a", "add a person (on someone without a page: theirs)" },
  { "1", "start a 1:1 with them" },
  { "y  o", "copy a way to reach them · open it (mail, chat…)" },
  { "R", "rename them everywhere (on `same as …?`: merge them into that person)" },
}

--- What involves each person: meetings (newest first), open to-dos, other mentions.
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

--- The one person a bare first name (`ana`, no page) probably is: the only other person whose
--- full name starts with it (`Ana López`). A guess, so it's only offered, never applied.
---@param p logpose.Person
---@param known logpose.Person[]
---@param you? logpose.Person
---@return logpose.Person?
local function same_as(p, known, you)
  local text = require("logpose.util.text")
  if p.name:find("%s") then
    return nil
  end
  local match
  for _, q in ipairs(known) do
    local first = q.name:match("^(%S+)%s")
    if q ~= p and q ~= you and first and text.plain(first) == text.plain(p.name) then
      if match then
        return nil -- two Anas: can't tell
      end
      match = q
    end
  end
  return match
end

---@param s logpose.ListState
---@return logpose.ListEntry[]
function M.collect(s)
  local people = require("logpose.people")
  local known = people.known(s.root)
  local inv = M.involvement(s.root, known)
  local fields = {}
  for _, it in ipairs(require("logpose.index").build(s.root)) do
    if it.kind == "person" then
      fields[it.file] = it.fields
    end
  end
  local me = require("logpose.config").get().me
  local you = me and people.find(known, me) -- `me`: not one of the people you work with
  local out = {}
  for _, p in ipairs(vim.tbl_filter(function(p)
    return p ~= you
  end, known)) do
    local projects, set = {}, {}
    for name, n in pairs(p.projects) do
      if n > 0 then
        table.insert(projects, name)
        set[name] = true
      end
    end
    table.sort(projects)
    local i = inv[p]
    local same = not p.page and same_as(p, known, you)
    local slugs = vim.tbl_keys(p.slugs)
    table.insert(out, {
      key = p.slug,
      file = p.page,
      person = p,
      projects = set,
      project_list = projects,
      inv = i,
      when = i.last or "",
      same_as = same,
      item = {
        kind = "person",
        file = p.page or "",
        text = table.concat(vim.list_extend({ p.name, p.role or "" }, p.aliases), " "),
        title = p.name,
        tags = projects,
        people = slugs,
        date = i.last,
        fields = (p.page and fields[p.page]) or { name = p.name },
      },
    })
  end
  return out
end

--- A person's page, or an error saying to add one first.
---@param e logpose.ListEntry
---@return string
local function page_of(e)
  if not e.person.page then
    error(("logpose: %s has no page yet (a adds one)"):format(e.person.name), 0)
  end
  return e.person.page
end

M.groupings = {
  {
    key = "page",
    label = "page",
    of = function(e)
      if e.person.page then
        return { { key = "page", label = "With a page", order = 1 } }
      end
      return { { key = "seen", label = "In your notes, no page yet", order = 2 } }
    end,
  },
  {
    key = "project",
    label = "project",
    none = "No project",
    ask = "New project: ",
    of = function(e, s)
      local out = {}
      for _, name in ipairs(e.project_list) do
        vim.list_extend(out, common.project_group(s, name))
      end
      return out
    end,
    targets = common.project_targets,
    move = function(s, e, from, to)
      local page = page_of(e)
      local fm = require("logpose.index").frontmatter(require("logpose.util.fs").read_lines(page) or {})
      to = to ~= "" and (require("logpose.project").normalize(to) or "") or ""
      local path = common.swap_in_list(s.root, page, "person", "projects", common.list(fm.projects), from, to)
      return vim.fn.fnamemodify(path, ":t:r")
    end,
  },
  {
    key = "role",
    label = "role",
    none = "No role",
    ask = "New role: ",
    of = function(e)
      local role = e.person.role
      return role and { { key = role, label = role } } or {}
    end,
    targets = function(s)
      local seen, out = {}, {}
      for _, e in ipairs(M.collect(s)) do
        local role = e.person.role
        if role and not seen[role] then
          seen[role] = true
          table.insert(out, { key = role, label = role })
        end
      end
      table.sort(out, function(a, b)
        return a.label:lower() < b.label:lower()
      end)
      table.insert(out, { key = "", label = "No role" })
      return out
    end,
    move = function(s, e, _, to)
      require("logpose.edit.save").note(s.root, page_of(e), "person", { role = to })
    end,
  },
  {
    key = "met",
    label = "last met",
    descending = true,
    none = "Never met",
    of = function(e)
      return common.month_group(e.inv.last)
    end,
  },
}

local function by_name(a, b)
  local people = require("logpose.people")
  return people.plain(a.person.name) < people.plain(b.person.name)
end

M.sorts = {
  {
    label = "recently met",
    cmp = function(a, b)
      local la, lb = a.inv.last or "", b.inv.last or ""
      if la ~= lb then
        return la > lb
      end
      if a.person.count ~= b.person.count then
        return a.person.count > b.person.count
      end
      return by_name(a, b)
    end,
  },
  { label = "by name", cmp = by_name },
  {
    label = "most involved",
    cmp = function(a, b)
      if a.person.count ~= b.person.count then
        return a.person.count > b.person.count
      end
      return by_name(a, b)
    end,
  },
}

function M.layout(ctx)
  local name_w, role_w = 12, 0
  for _, e in ipairs(ctx.entries) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(e.person.name))
    role_w = math.max(role_w, vim.fn.strdisplaywidth(e.person.role or ""))
  end
  ctx.name_w, ctx.role_w = math.min(name_w, 28), math.min(role_w, 22)
end

---@param e logpose.ListEntry
---@param ctx table
---@return table[]
function M.row(e, ctx)
  local people = require("logpose.people")
  local date = require("logpose.util.date")
  local p, i = e.person, e.inv
  local chunks = { { lists.fit(p.name, ctx.name_w) } }
  if ctx.role_w > 0 then
    table.insert(chunks, { "  " })
    table.insert(chunks, { lists.fit(p.role or "", ctx.role_w), "LogposeListMeta" })
  end
  local meta = {}
  local reach = vim.tbl_map(function(c)
    return c.shown
  end, people.contacts_of(p))
  if #reach > 0 then
    table.insert(meta, { table.concat(reach, " · "), "LogposeListPeople" })
  end
  if i.last then
    table.insert(meta, { "met " .. date.relative(i.last, date.today()), "LogposeListMeta" })
  end
  if #i.todos > 0 then
    table.insert(meta, { ("☐ %d open"):format(#i.todos), "LogposeListTodos" })
  end
  if not p.page then
    table.insert(meta, { ("%d mention%s"):format(p.count, p.count == 1 and "" or "s"), "LogposeListMeta" })
  end
  if e.same_as then
    table.insert(meta, { ("same as %s? R merges"):format(e.same_as.name), "LogposeListTodos" })
  end
  if ctx.all_projects and ctx.group ~= "project" and #e.project_list > 0 then
    table.insert(meta, { "◆ " .. table.concat(e.project_list, ", "), "LogposeListMeta" })
  end
  return common.with_meta(chunks, meta)
end

function M.details(e)
  local date = require("logpose.util.date")
  local i, out = e.inv, {}
  for k = 1, math.min(5, #i.meetings) do
    local it = i.meetings[k]
    table.insert(out, {
      chunks = {
        { "◷ ", "LogposeListMeta" },
        { ("%s  %s"):format(it.date and date.short(it.date) or "", it.title or "") },
      },
      file = it.file,
      lnum = it.lnum,
    })
  end
  for k = 1, math.min(5, #i.todos) do
    local it = i.todos[k]
    table.insert(out, {
      chunks = {
        { "☐ ", "LogposeListTodos" },
        { ("%s  · %s"):format(it.text, it.title or vim.fs.basename(it.file)) },
      },
      file = it.file,
      lnum = it.lnum,
    })
  end
  for k = 1, math.min(5, #i.mentions) do
    local it = i.mentions[k]
    table.insert(out, {
      chunks = { { it.kind == "task" and "▣ " or "✎ ", "LogposeListMeta" }, { it.title or it.text } },
      file = it.file,
      lnum = it.lnum,
    })
  end
  return out
end

--- Add or edit a person: the form, then back to the list.
---@param s logpose.ListState
---@param p? logpose.Person
---@param done fun(key?: string)
---@param defaults? table
local function form(s, p, done, defaults)
  local function back(path)
    done(path and vim.fn.fnamemodify(path, ":t:r") or (p and p.slug))
  end
  if p and p.page then
    require("logpose.edit").open(p.page, { root = s.root, on_save = back })
  else
    require("logpose.edit").open_new_note(
      s.root,
      "person",
      vim.tbl_extend("force", { name = p and p.name, project = s.project }, defaults or {}),
      { on_save = back }
    )
  end
end

function M.open(e, s)
  if e.person.page then
    vim.cmd.edit(vim.fn.fnameescape(e.person.page))
  else
    form(s, e.person, function(key)
      lists.render(s, key)
    end)
  end
end

function M.edit(e, s, done)
  form(s, e.person, done)
end

function M.add(s, group, done)
  local e = lists.entry_at(s)
  if e and not e.person.page then
    return form(s, e.person, done) -- someone without a page: theirs
  end
  local by = s.view.groupings[s.group].key
  local defaults = {}
  if by == "project" and group and group ~= "" then
    defaults.project = group
  elseif by == "role" and group and group ~= "" then
    defaults.role = group
  end
  form(s, nil, done, defaults)
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

function M.keys(s, map, h)
  local function person()
    local e = h.entry_at(s)
    return e and e.person
  end
  map("1", function()
    local p = person()
    if not p then
      return
    end
    local key
    for _, t in ipairs(require("logpose.notes.meeting").types()) do
      if t.spec.person then
        key = key or t.key
      end
    end
    require("logpose.edit").open_new_note(s.root, "meeting", { type = key, title = p.name, project = s.project })
  end, "Start a 1:1")
  map("y", function()
    local p = person()
    if p then
      with_contact(p, false, function(c)
        vim.fn.setreg('"', c.value)
        pcall(vim.fn.setreg, "+", c.value)
        ui.notify(("logpose: copied %s's %s: %s"):format(p.name, c.label, c.value), vim.log.levels.INFO)
      end)
    end
  end, "Copy a way to reach them")
  map("o", function()
    local p = person()
    if p then
      with_contact(p, true, function(c)
        vim.ui.open(c.url)
      end)
    end
  end, "Open a way to reach them")
  map("R", function()
    local e = h.entry_at(s)
    local p = e and e.person
    if not p then
      return
    end
    -- renaming `ana` to `Ana López` makes them one person: offer that when it's the likely one
    vim.ui.input(
      { prompt = ("New name for %s: "):format(p.name), default = e.same_as and e.same_as.name or p.name },
      ui.safely(function(input)
        if input and vim.trim(input) ~= "" and vim.trim(input) ~= p.name then
          require("logpose.people.rename").rename(p.slug, input, {
            after = function()
              h.refresh(require("logpose.util.text").slugify(input))
            end,
          })
        end
      end)
    )
  end, "Rename")
end

M.command = lists.command_for(M)

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

function M.complete(arglead, _)
  return require("logpose.search").complete(arglead, { "people" })
end

return M

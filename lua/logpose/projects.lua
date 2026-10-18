--- Projects at a glance: `:Logpose projects` (the manager screen) and the quick switcher behind
--- `:Logpose project`. Both show, per project, what needs attention: overdue and blocked tasks,
--- work in progress, and how recently anything happened.
local config = require("logpose.config")
local date = require("logpose.util.date")
local project = require("logpose.project")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.projects")

--- Tasks due within this many days count as "due soon".
M.DUE_SOON_DAYS = 3

M.HELP = {
  "Projects",
  "",
  "  <CR>   switch to the project (on a detail line: open it)",
  "  <Tab>  show / hide what's going on in it",
  "  b      its board                 n  its project page",
  "  t      its open tasks            f  its notes",
  "  a      add a project             p  link a repo folder",
  "  R      rename                    M  merge into another project",
  "  D      archive (hide)            U  restore an archived one",
  "  A      show / hide archived      c  back to auto-detect",
  "  r      refresh                   q  close",
}

---@class logpose.ProjectEntry
---@field file string
---@field lnum integer
---@field title string
---@field note? string   extra text (block reason, due date…)

---@class logpose.ProjectStats
---@field name string
---@field title string            display name (page title, else the name)
---@field description? string
---@field paths string[]
---@field archived boolean
---@field merged_into? string
---@field page? string            path of its project page
---@field open integer            tasks not done
---@field doing integer           tasks in the start column (In progress)
---@field blocked integer
---@field overdue integer
---@field due_soon integer
---@field done integer
---@field meetings integer
---@field notes integer           other notes
---@field mtime integer           newest change to any of its files (0: none)
---@field last? string            that as "today", "3d ago"…
---@field stale boolean           nothing changed for `review.stale_days`
---@field in_progress logpose.ProjectEntry[]
---@field blocked_list logpose.ProjectEntry[]
---@field due_list logpose.ProjectEntry[]   overdue and due soon, soonest first
---@field last_meeting? logpose.ProjectEntry
---@field recent_notes logpose.ProjectEntry[]

--- "today", "yesterday", "3d ago", "2w ago", "4mo ago".
---@param mtime integer
---@param now integer
---@return string
function M.ago(mtime, now)
  local days = math.floor((now - mtime) / 86400)
  if os.date("%Y-%m-%d", mtime) == os.date("%Y-%m-%d", now) then
    return "today"
  elseif days <= 1 then
    return "yesterday"
  elseif days < 14 then
    return days .. "d ago"
  elseif days < 60 then
    return math.floor(days / 7) .. "w ago"
  elseif days < 730 then
    return math.floor(days / 30) .. "mo ago"
  end
  return math.floor(days / 365) .. "y ago"
end

--- Everything the manager and the switcher show, one entry per project (archived included),
--- most recently active first.
---@param root string
---@param today? string
---@return logpose.ProjectStats[]
function M.stats(root, today)
  today = today or date.today()
  local cfg = config.get()
  local pages = project.pages(root)
  local uv = vim.uv or vim.loop
  local by_name, list = {}, {}
  local function entry(name)
    if not by_name[name] then
      local page = pages[name] or {}
      by_name[name] = {
        name = name,
        title = page.title or name,
        description = page.description,
        paths = page.paths or {},
        archived = page.archived or false,
        merged_into = page.merged_into,
        page = page.path,
        open = 0,
        doing = 0,
        blocked = 0,
        overdue = 0,
        due_soon = 0,
        done = 0,
        meetings = 0,
        notes = 0,
        mtime = 0,
        in_progress = {},
        blocked_list = {},
        due_list = {},
        recent_notes = {},
      }
      table.insert(list, by_name[name])
    end
    return by_name[name]
  end
  for _, name in ipairs(project.known(root, { archived = true })) do
    entry(name)
  end
  local mtimes = {}
  local function mtime(path)
    if mtimes[path] == nil then
      local st = uv.fs_stat(path)
      mtimes[path] = st and st.mtime.sec or 0
    end
    return mtimes[path]
  end
  for _, it in ipairs(require("logpose.index").build(root)) do
    local name = it.kind == "note" and it.project and project.normalize(it.project)
    if name then
      local e = entry(name)
      local ref = { file = it.file, lnum = it.lnum or 1, title = it.title or vim.fs.basename(it.file) }
      if it.note_type == "task" then
        if it.archived or it.status == cfg.board.done then
          e.done = e.done + 1
        else
          e.open = e.open + 1
          if it.status == cfg.board.start then
            e.doing = e.doing + 1
            table.insert(e.in_progress, ref)
          end
          if it.blocked then
            e.blocked = e.blocked + 1
            table.insert(e.blocked_list, vim.tbl_extend("force", ref, { note = it.blocked }))
          end
          if it.due and it.due:match("^%d%d%d%d%-%d%d%-%d%d$") then
            local d = date.diff_days(today, it.due)
            if d < 0 then
              e.overdue = e.overdue + 1
            elseif d <= M.DUE_SOON_DAYS then
              e.due_soon = e.due_soon + 1
            end
            if d <= M.DUE_SOON_DAYS then
              table.insert(e.due_list, vim.tbl_extend("force", ref, { due = it.due, days = d }))
            end
          end
        end
      elseif it.note_type == "meeting" then
        e.meetings = e.meetings + 1
        if not e.last_meeting or (it.date or "") > (e.last_meeting.date or "") then
          e.last_meeting = vim.tbl_extend("force", ref, { date = it.date })
        end
      elseif it.note_type ~= "project" then
        e.notes = e.notes + 1
        table.insert(e.recent_notes, vim.tbl_extend("force", ref, { mtime = mtime(it.file) }))
      end
      e.mtime = math.max(e.mtime, mtime(it.file))
    end
  end
  local now = date._now()
  local stale_after = cfg.review.stale_days * 86400
  for _, e in ipairs(list) do
    if e.page then
      e.mtime = math.max(e.mtime, mtime(e.page))
    end
    e.last = e.mtime > 0 and M.ago(e.mtime, now) or nil
    e.stale = e.mtime > 0 and now - e.mtime > stale_after
    table.sort(e.due_list, function(a, b)
      return a.due < b.due
    end)
    table.sort(e.recent_notes, function(a, b)
      return a.mtime > b.mtime
    end)
    while #e.recent_notes > 3 do
      table.remove(e.recent_notes)
    end
  end
  table.sort(list, function(a, b)
    if a.mtime ~= b.mtime then
      return a.mtime > b.mtime
    end
    return a.name < b.name
  end)
  return list
end

--- The one-line summary of a project, as highlighted chunks:
--- "5 open (1 in progress) · 1 overdue · 1 blocked · 2 meetings".
---@param e logpose.ProjectStats
---@return { [1]: string, [2]: string? }[]
function M.summary(e)
  local parts = {}
  local function add(n, what, hl)
    if n > 0 then
      table.insert(parts, { ("%d %s"):format(n, what), hl })
    end
  end
  if e.open > 0 then
    local doing = require("logpose.taskfile").label(config.get().board.start):lower()
    add(e.open, e.doing > 0 and not e.archived and ("open (%d %s)"):format(e.doing, doing) or "open")
  end
  if not e.archived then
    add(e.overdue, "overdue", "DiagnosticError")
    add(e.due_soon, "due soon", "DiagnosticWarn")
    add(e.blocked, "blocked", "DiagnosticError")
  end
  if e.open == 0 then
    add(e.done, "done", "Comment")
  end
  add(e.meetings, e.meetings == 1 and "meeting" or "meetings")
  add(e.notes, e.notes == 1 and "note" or "notes")
  if #parts == 0 then
    return { { e.page and "project page only" or "nothing yet", "Comment" } }
  end
  local out = {}
  for i, p in ipairs(parts) do
    if i > 1 then
      table.insert(out, { " · ", "Comment" })
    end
    table.insert(out, p)
  end
  return out
end

---@class logpose.ProjectsLine
---@field chunks { [1]: string, [2]: string? }[]
---@field project? string    a project row
---@field archived? boolean
---@field file? string       a detail line that opens a file
---@field lnum? integer

--- What's going on in a project, as lines (used under an expanded row and in the switcher's
--- preview).
---@param e logpose.ProjectStats
---@param indent? string
---@return logpose.ProjectsLine[]
function M.details(e, indent)
  indent = indent or ""
  local lines = {} ---@type logpose.ProjectsLine[]
  local function add(chunks, extra)
    table.insert(chunks, 1, { indent })
    table.insert(lines, vim.tbl_extend("force", { chunks = chunks }, extra or {}))
  end
  if e.description then
    add({ { e.description, "Comment" } })
  end
  if e.title ~= e.name then
    add({ { "name: ", "Comment" }, { e.name } })
  end
  if #e.paths > 0 then
    add({ { "repo: ", "Comment" }, { table.concat(e.paths, ", ") } })
  end
  if e.merged_into then
    add({ { "merged into ", "Comment" }, { e.merged_into, "Identifier" } })
  end
  local function section(title, entries, fmt)
    if #entries == 0 then
      return
    end
    add({ { title, "Title" } })
    for _, x in ipairs(entries) do
      local text, hl, note_hl = fmt(x)
      add({ { "  • " }, { x.title, hl }, { text or "", note_hl or "Comment" } }, { file = x.file, lnum = x.lnum })
    end
  end
  local doing = require("logpose.taskfile").label(config.get().board.start)
  section(doing, e.in_progress, function()
    return nil
  end)
  section("Blocked", e.blocked_list, function(x)
    return "  " .. x.note, nil, "DiagnosticError"
  end)
  section("Due", e.due_list, function(x)
    if x.days < 0 then
      return ("  overdue %dd"):format(-x.days), nil, "DiagnosticError"
    elseif x.days == 0 then
      return "  today", nil, "DiagnosticWarn"
    end
    return ("  in %dd"):format(x.days), nil, "DiagnosticWarn"
  end)
  if e.last_meeting then
    section("Last meeting", { e.last_meeting }, function(x)
      return x.date and ("  " .. x.date) or nil
    end)
  end
  section("Recent notes", e.recent_notes, function()
    return nil
  end)
  if #lines == 0 then
    add({ { "Nothing here yet. n opens its project page.", "Comment" } })
  end
  return lines
end

--- The manager screen, as lines of chunks.
---@param root string
---@param opts? { show_archived?: boolean, expanded?: table<string, boolean>, today?: string }
---@return logpose.ProjectsLine[]
function M.build(root, opts)
  opts = opts or {}
  local list = M.stats(root, opts.today)
  local current, source = project.resolve(root)
  local lines = {} ---@type logpose.ProjectsLine[]
  local function add(chunks, extra)
    table.insert(lines, vim.tbl_extend("force", { chunks = chunks }, extra or {}))
  end
  local active, archived = {}, {}
  local width, sum_width = 0, 0
  for _, e in ipairs(list) do
    table.insert(e.archived and archived or active, e)
  end
  for _, e in ipairs(list) do
    if opts.show_archived or not e.archived then
      width = math.max(width, vim.fn.strdisplaywidth(e.title))
      local w = 0
      for _, c in ipairs(M.summary(e)) do
        w = w + vim.fn.strdisplaywidth(c[1])
      end
      sum_width = math.max(sum_width, w)
    end
  end

  add({ { "# Projects", "Title" } })
  add({})
  local how =
    { explicit = "pinned", path = "from projects.paths", page = "from its repo folder", git = "from the git repo" }
  if current then
    add({
      { "Active: ", "Comment" },
      { project.title(root, current), "Title" },
      { (" (%s)"):format(how[source] or source), "Comment" },
    })
  else
    add({ { "Active: ", "Comment" }, { "none", "Title" }, { " (logpose follows the repo you are in)", "Comment" } })
  end
  local function row(e)
    local is_current = e.name == current
    local faded = e.archived or e.stale
    local pad = string.rep(" ", width - vim.fn.strdisplaywidth(e.title))
    local chunks = {
      { "  " },
      { is_current and "● " or "  ", "DiagnosticOk" },
      { (opts.expanded or {})[e.name] and "▾ " or "▸ ", "Comment" },
      { e.title, faded and "Comment" or (is_current and "Title" or (project.hl(root, e.name) or "Identifier")) },
      { pad .. "   " },
    }
    local w = 0
    for _, c in ipairs(M.summary(e)) do
      table.insert(chunks, faded and { c[1], "Comment" } or c)
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    if e.last then
      table.insert(chunks, { string.rep(" ", sum_width - w + 3) .. e.last, "Comment" })
    end
    add(chunks, { project = e.name, archived = e.archived })
    if (opts.expanded or {})[e.name] then
      for _, d in ipairs(M.details(e, "        ")) do
        table.insert(lines, d)
      end
      add({})
    end
  end
  add({})
  if #active == 0 then
    add({ { "  No projects yet. Press a to add one.", "Comment" } })
  end
  for _, e in ipairs(active) do
    row(e)
  end
  if #archived > 0 then
    add({})
    add({
      { ("## Archived (%d)"):format(#archived), "Title" },
      { opts.show_archived and "" or "  A shows them", "Comment" },
    })
    if opts.show_archived then
      add({})
      for _, e in ipairs(archived) do
        row(e)
      end
    end
  end
  add({})
  add({
    {
      "<CR> switch · <Tab> details · b board · n page · a add · R rename · M merge · D archive · ? help",
      "Comment",
    },
  })
  return lines
end

--- Join chunks into text, and highlight them in `buf` at `row`.
---@param buf? integer
---@param row integer 0-based
---@param chunks { [1]: string, [2]: string? }[]
---@return string
local function put(buf, row, chunks)
  local col, parts = 0, {}
  for _, c in ipairs(chunks) do
    if buf and c[2] and #c[1] > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, row, col, { end_col = col + #c[1], hl_group = c[2] })
    end
    table.insert(parts, c[1])
    col = col + #c[1]
  end
  return table.concat(parts)
end

---@param buf integer
---@param root string
---@param focus? string project to put the cursor on
local function render(buf, root, focus)
  local lines = M.build(root, {
    show_archived = vim.b[buf].logpose_show_archived,
    expanded = vim.b[buf].logpose_expanded or {},
  })
  local texts, rows = {}, {}
  for i, l in ipairs(lines) do
    texts[i] = put(nil, 0, l.chunks)
    rows[i] = (l.project and { name = l.project, archived = l.archived })
      or (l.file and { file = l.file, lnum = l.lnum })
      or false
  end
  vim.b[buf].logpose_projects = rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, l in ipairs(lines) do
    put(buf, i - 1, l.chunks)
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  local target
  for i, r in ipairs(rows) do
    if r and r.name and (r.name == focus or (not focus and not target)) then
      target = i
      if focus then
        break
      end
    end
  end
  if target and (focus or vim.api.nvim_win_get_cursor(win)[1] < 5) then
    pcall(vim.api.nvim_win_set_cursor, win, { target, 4 })
  end
end

---@param buf integer
---@return { name?: string, archived?: boolean, file?: string, lnum?: integer }?
local function under_cursor(buf)
  return (vim.b[buf].logpose_projects or {})[vim.api.nvim_win_get_cursor(0)[1]] or nil
end

--- The project row the cursor is on, or the one a detail line belongs to.
---@param buf integer
---@return { name: string, archived: boolean }?
local function project_at_cursor(buf)
  local rows = vim.b[buf].logpose_projects or {}
  for i = vim.api.nvim_win_get_cursor(0)[1], 1, -1 do
    local r = rows[i]
    if r and r.name then
      return r
    end
  end
end

--- Ask for a project name.
---@param prompt string
---@param default? string
---@param fn fun(name: string, typed: string) the slug and the name as typed
local function ask(prompt, default, fn)
  vim.ui.input(
    { prompt = prompt, default = default },
    ui.safely(function(input)
      local typed = input and vim.trim(input) or ""
      local name = project.normalize(typed)
      if name then
        fn(name, typed)
      end
    end)
  )
end

--- `~/x` for paths under the home folder.
---@param path string
---@return string
local function tilde(path)
  return vim.fn.fnamemodify(path, ":~")
end

--- A folder to suggest when linking a repo: the git repo of the window you came from.
---@return string
local function suggested_repo()
  local alt = vim.fn.bufnr("#")
  local name = alt > 0 and vim.api.nvim_buf_get_name(alt) or ""
  local repo = vim.fs.root(name ~= "" and name or vim.fn.getcwd(), ".git")
  local root = config.resolve_root()
  if repo and not (root and vim.startswith(repo, root)) then
    return tilde(repo)
  end
  return ""
end

--- Ask for a repo folder (empty: none).
---@param fn fun(path?: string)
local function ask_repo(fn)
  vim.ui.input(
    { prompt = "Repo folder (empty for none): ", default = suggested_repo(), completion = "dir" },
    ui.safely(function(input)
      input = input and vim.trim(input):gsub("/+$", "") or ""
      if input == "" then
        return fn(nil)
      end
      if vim.fn.isdirectory(vim.fn.expand(input)) == 0 then
        error(("logpose: %s is not a folder"):format(input), 0)
      end
      fn((tilde(vim.fn.fnamemodify(vim.fn.expand(input), ":p")):gsub("/+$", "")))
    end)
  )
end

---@param root string
---@return integer buf
function M.open(root)
  local name = "logpose://projects"
  local existing = vim.fn.bufnr(name)
  if existing > 0 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "logpose-projects"
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo[0][0].wrap = false
  vim.wo[0][0].cursorline = true
  vim.b[buf].logpose_expanded = {}
  render(buf, root)

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  --- Run `fn(project)` on the project under the cursor (or the one its detail line belongs to).
  local function on_project(fn, allow_archived)
    return function()
      local r = project_at_cursor(buf)
      if not r then
        return
      end
      if r.archived and not allow_archived then
        ui.notify(("logpose: %s is archived (U restores it)"):format(r.name), vim.log.levels.INFO)
        return
      end
      fn(r.name, r)
    end
  end

  map("<CR>", function()
    local r = under_cursor(buf)
    if r and r.file then
      vim.cmd.edit(vim.fn.fnameescape(r.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { r.lnum or 1, 0 })
      return
    end
    on_project(function(p)
      project.set(p)
      render(buf, root, p)
    end)()
  end, "Switch to the project, or open the line")
  map(
    "<Tab>",
    on_project(function(p)
      local expanded = vim.b[buf].logpose_expanded or {}
      expanded[p] = not expanded[p] or nil
      vim.b[buf].logpose_expanded = expanded
      render(buf, root, p)
    end, true),
    "Show / hide details"
  )
  map("c", function()
    project.set(nil)
    render(buf, root)
  end, "Back to auto-detect")
  map(
    "b",
    on_project(function(p)
      require("logpose.board").open_board(root, { project = p })
    end, true),
    "Board"
  )
  map(
    "n",
    on_project(function(p)
      require("logpose.notes.topic").project_page(root, p)
    end, true),
    "Project page"
  )
  map(
    "t",
    on_project(function(p)
      vim.cmd("Logpose find tasks open project:" .. p)
    end, true),
    "Open tasks"
  )
  map(
    "f",
    on_project(function(p)
      vim.cmd("Logpose find notes project:" .. p)
    end, true),
    "Notes"
  )
  map("a", function()
    ask("New project: ", nil, function(p, typed)
      if project.pages(root)[p] then
        ui.notify(("logpose: %s already exists"):format(p), vim.log.levels.INFO)
        return render(buf, root, p)
      end
      ask_repo(function(repo)
        project.add(root, typed, repo and { repo } or nil)
        render(buf, root, p)
      end)
    end)
  end, "Add a project")
  map(
    "p",
    on_project(function(p)
      ask_repo(function(repo)
        if not repo then
          return
        end
        local page = project.pages(root)[p]
        local paths = vim.deepcopy(page and page.paths or {})
        if not vim.tbl_contains(paths, repo) then
          table.insert(paths, repo)
        end
        project.set_page_field(root, p, "paths", "[" .. table.concat(paths, ", ") .. "]")
        project.changed()
        ui.notify(("logpose: %s now belongs to %s"):format(repo, p), vim.log.levels.INFO)
      end)
    end, true),
    "Link a repo folder"
  )
  map(
    "R",
    on_project(function(p)
      ask(("Rename %s to: "):format(p), p, function(new)
        if new ~= p then
          vim.b[buf].logpose_focus = new
          require("logpose.maintenance").move_project(p, new, {})
        end
      end)
    end, true),
    "Rename"
  )
  map(
    "M",
    on_project(function(p)
      local others = vim.tbl_filter(function(n)
        return n ~= p
      end, project.known(root))
      if #others == 0 then
        ui.notify("logpose: there's no other project to merge into", vim.log.levels.INFO)
        return
      end
      vim.ui.select(
        others,
        {
          prompt = ("Merge %s into"):format(p),
          format_item = function(n)
            local t = project.title(root, n)
            return t ~= n and ("%s  (%s)"):format(n, t) or n
          end,
        },
        ui.safely(function(target)
          if target then
            vim.b[buf].logpose_focus = target
            require("logpose.maintenance").move_project(p, target, { merge = true })
          end
        end)
      )
    end, true),
    "Merge into another project"
  )
  map(
    "D",
    on_project(function(p)
      vim.ui.select(
        { "Archive", "Cancel" },
        { prompt = ("Archive %s? Its notes and tasks stay, hidden from lists and the board"):format(p) },
        ui.safely(function(choice)
          if choice == "Archive" then
            project.set_archived(root, p, true)
            ui.notify(("logpose: archived %s (U restores it)"):format(p), vim.log.levels.INFO)
            render(buf, root)
          end
        end)
      )
    end),
    "Archive"
  )
  map(
    "U",
    on_project(function(p, r)
      if not r.archived then
        return
      end
      project.set_archived(root, p, false)
      ui.notify(("logpose: restored %s"):format(p), vim.log.levels.INFO)
      render(buf, root, p)
    end, true),
    "Restore"
  )
  map("A", function()
    vim.b[buf].logpose_show_archived = not vim.b[buf].logpose_show_archived
    render(buf, root)
  end, "Show / hide archived")
  map("r", function()
    render(buf, root)
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

  local group = vim.api.nvim_create_augroup("logpose.projects", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LogposeProjectChanged",
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return true
      end
      local focus = vim.b[buf].logpose_focus
      vim.b[buf].logpose_focus = nil
      render(buf, root, focus)
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = buf,
    callback = function()
      render(buf, root)
    end,
  })
  return buf
end

---@param _ logpose.CommandOpts
function M.command(_)
  config.with_root(ui.safely(function(root)
    M.open(root)
  end))
end

--- The quick switcher: projects in the picker, the ones you switched to recently first, each
--- previewing what's going on in it. Choosing one makes it the active project.
---@param root string
---@param opts? { on_switch?: fun(name?: string) }
function M.switch(root, opts)
  opts = opts or {}
  local list = vim.tbl_filter(function(e)
    return not e.archived
  end, M.stats(root))
  local current = project.resolve(root)
  local rank = {}
  for i, name in ipairs(project.recent()) do
    rank[name] = i
  end
  -- the active project first, then recently switched to, then by activity (already sorted)
  local pos = {}
  for i, e in ipairs(list) do
    pos[e] = i
  end
  table.sort(list, function(a, b)
    if (a.name == current) ~= (b.name == current) then
      return a.name == current
    end
    local ra, rb = rank[a.name] or math.huge, rank[b.name] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return pos[a] < pos[b]
  end)
  local width = 0
  for _, e in ipairs(list) do
    width = math.max(width, vim.fn.strdisplaywidth(e.title))
  end
  local items = {}
  for _, e in ipairs(list) do
    local summary = {}
    for _, c in ipairs(M.summary(e)) do
      table.insert(summary, c[1])
    end
    local preview = { "# " .. e.title, "" }
    vim.list_extend(preview, { table.concat(summary), "" })
    for _, d in ipairs(M.details(e)) do
      local t = {}
      for _, c in ipairs(d.chunks) do
        table.insert(t, c[1])
      end
      table.insert(preview, table.concat(t))
    end
    if e.last then
      vim.list_extend(preview, { "", "Last change: " .. e.last })
    end
    table.insert(items, {
      display = ("%s %s%s  %s"):format(
        e.name == current and "●" or " ",
        e.title,
        string.rep(" ", width - vim.fn.strdisplaywidth(e.title)),
        table.concat(summary)
      ),
      preview = table.concat(preview, "\n"),
      name = e.name,
    })
  end
  table.insert(items, { display = "+ New project…", preview = "Create a project page and switch to it.", new = true })
  table.insert(items, {
    display = "  Auto-detect",
    preview = "Unpin the project: logpose follows the repo you are in.",
    clear = true,
  })
  local function done(name)
    if opts.on_switch then
      opts.on_switch(name)
    end
  end
  require("logpose.picker").pick(items, {
    prompt = "Switch project",
    on_choice = ui.safely(function(item)
      if item.clear then
        project.set(nil)
        return done(nil)
      end
      if not item.new then
        project.set(item.name)
        return done(item.name)
      end
      ask("New project: ", nil, function(p, typed)
        if not project.pages(root)[p] then
          project.add(root, typed)
        end
        project.set(p)
        done(p)
      end)
    end),
  })
end

return M

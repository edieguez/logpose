--- `:Logpose projects`: every project with what's going on in it. Switch to one, open its board,
--- page or tasks, add, rename, archive and restore projects.
local config = require("logpose.config")
local project = require("logpose.project")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.projects")

M.HELP = {
  "Projects",
  "",
  "  <CR>  switch to this project      c  back to auto-detect",
  "  b     its board                   n  its project page (notes)",
  "  t     its open tasks              f  its notes",
  "  a     add a project               R  rename",
  "  D     archive (hide)              U  restore an archived one",
  "  A     show / hide archived        r  refresh",
  "  q     close                       ?  this help",
}

---@class logpose.ProjectStats
---@field name string
---@field archived boolean
---@field page? string path of its project page
---@field open integer tasks not done
---@field doing integer tasks in the start column (In progress)
---@field blocked integer
---@field done integer
---@field meetings integer
---@field notes integer other notes (topic notes, daily notes with the project…)
---@field last? string date of the most recently changed file

--- One entry per project (archived ones included), sorted by name.
---@param root string
---@return logpose.ProjectStats[]
function M.stats(root)
  local cfg = config.get()
  local pages = project.pages(root)
  local by_name, list = {}, {}
  local function entry(name)
    if not by_name[name] then
      local page = pages[name]
      by_name[name] = {
        name = name,
        archived = page and page.archived or false,
        page = page and page.path,
        open = 0,
        doing = 0,
        blocked = 0,
        done = 0,
        meetings = 0,
        notes = 0,
        mtime = 0,
      }
      table.insert(list, by_name[name])
    end
    return by_name[name]
  end
  for _, name in ipairs(project.known(root, { archived = true })) do
    entry(name)
  end
  local uv = vim.uv or vim.loop
  for _, it in ipairs(require("logpose.index").build(root)) do
    local name = it.kind == "note" and it.project and project.normalize(it.project)
    if name then
      local e = entry(name)
      if it.note_type == "task" then
        if it.archived or it.status == cfg.board.done then
          e.done = e.done + 1
        else
          e.open = e.open + 1
          if it.status == cfg.board.start then
            e.doing = e.doing + 1
          end
          if it.blocked then
            e.blocked = e.blocked + 1
          end
        end
      elseif it.note_type == "meeting" then
        e.meetings = e.meetings + 1
      elseif it.note_type ~= "project" then
        e.notes = e.notes + 1
      end
      local st = uv.fs_stat(it.file)
      if st and st.mtime.sec > e.mtime then
        e.mtime = st.mtime.sec
      end
    end
  end
  for _, e in ipairs(list) do
    if e.page then
      local st = uv.fs_stat(e.page)
      if st and st.mtime.sec > e.mtime then
        e.mtime = st.mtime.sec
      end
    end
    e.last = e.mtime > 0 and os.date("%Y-%m-%d", e.mtime) or nil
    e.mtime = nil
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

--- The summary of a project as highlighted chunks: "2 in progress · 3 open · 1 blocked · …".
---@param e logpose.ProjectStats
---@return { [1]: string, [2]: string? }[]
local function summary(e)
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
    add(e.blocked, "blocked", "DiagnosticError")
  end
  add(e.done, "done", "Comment")
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
---@field project? string
---@field archived? boolean

--- The screen, as lines of chunks.
---@param root string
---@param opts? { show_archived?: boolean }
---@return logpose.ProjectsLine[]
function M.build(root, opts)
  opts = opts or {}
  local list = M.stats(root)
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
      width = math.max(width, #e.name)
      local w = 0
      for _, c in ipairs(summary(e)) do
        w = w + vim.fn.strdisplaywidth(c[1])
      end
      sum_width = math.max(sum_width, w)
    end
  end

  add({ { "# Projects", "Title" } })
  add({})
  local how = { explicit = "pinned", path = "from projects.paths", git = "from the git repo" }
  if current then
    add({ { "Active: ", "Comment" }, { current, "Title" }, { (" (%s)"):format(how[source] or source), "Comment" } })
  else
    add({ { "Active: ", "Comment" }, { "none", "Title" }, { " (logpose follows the git repo you are in)", "Comment" } })
  end
  local function row(e)
    local is_current = e.name == current
    local chunks = {
      { "  " },
      { is_current and "● " or "  ", "DiagnosticOk" },
      { ("%-" .. width .. "s"):format(e.name), e.archived and "Comment" or (is_current and "Title" or "Identifier") },
      { "   " },
    }
    local w = 0
    for _, c in ipairs(summary(e)) do
      table.insert(chunks, c)
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    if e.last then
      table.insert(chunks, { string.rep(" ", sum_width - w + 3) .. e.last, "Comment" })
    end
    add(chunks, { project = e.name, archived = e.archived })
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
      "<CR> switch · b board · n notes · t tasks · a add · R rename · D archive · c auto-detect · ? help",
      "Comment",
    },
  })
  return lines
end

---@param buf integer
---@param root string
---@param focus? string project to put the cursor on
local function render(buf, root, focus)
  local lines = M.build(root, { show_archived = vim.b[buf].logpose_show_archived })
  local texts, rows = {}, {}
  for i, l in ipairs(lines) do
    local t = {}
    for _, c in ipairs(l.chunks) do
      table.insert(t, c[1])
    end
    texts[i] = table.concat(t)
    rows[i] = l.project and { name = l.project, archived = l.archived } or false
  end
  vim.b[buf].logpose_projects = rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, l in ipairs(lines) do
    local col = 0
    for _, c in ipairs(l.chunks) do
      if c[2] and #c[1] > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = col + #c[1], hl_group = c[2] })
      end
      col = col + #c[1]
    end
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  local target
  for i, r in ipairs(rows) do
    if r and (r.name == focus or (not focus and not target)) then
      target = i
      if focus then
        break
      end
    end
  end
  if target and (focus or vim.api.nvim_win_get_cursor(win)[1] == 1) then
    pcall(vim.api.nvim_win_set_cursor, win, { target, 4 })
  end
end

---@param buf integer
---@return { name: string, archived: boolean }?
local function under_cursor(buf)
  return (vim.b[buf].logpose_projects or {})[vim.api.nvim_win_get_cursor(0)[1]] or nil
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
  render(buf, root)

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  --- Run `fn(project)` on the project under the cursor.
  local function on_row(fn, allow_archived)
    return function()
      local r = under_cursor(buf)
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

  map(
    "<CR>",
    on_row(function(p)
      project.set(p)
      render(buf, root, p)
    end),
    "Switch to this project"
  )
  map("c", function()
    project.set(nil)
    render(buf, root)
  end, "Back to auto-detect")
  map(
    "b",
    on_row(function(p)
      require("logpose.board").open_board(root, { project = p })
    end, true),
    "Board"
  )
  map(
    "n",
    on_row(function(p)
      require("logpose.notes.topic").project_page(root, p)
    end, true),
    "Project page"
  )
  map(
    "t",
    on_row(function(p)
      vim.cmd("Logpose find tasks open project:" .. p)
    end, true),
    "Open tasks"
  )
  map(
    "f",
    on_row(function(p)
      vim.cmd("Logpose find notes project:" .. p)
    end, true),
    "Notes"
  )
  map("a", function()
    ask("New project: ", nil, function(p, typed)
      if project.pages(root)[p] then
        ui.notify(("logpose: %s already exists"):format(p), vim.log.levels.INFO)
      else
        require("logpose.notes.topic").project_page(root, typed, { open = false })
        project.changed()
      end
      render(buf, root, p)
    end)
  end, "Add a project")
  map(
    "R",
    on_row(function(p)
      ask(("Rename %s to: "):format(p), p, function(new)
        if new ~= p then
          -- Same preview and confirmation as :Logpose rename-project; the screen refreshes
          -- through LogposeProjectChanged when it's applied.
          vim.b[buf].logpose_focus = new
          require("logpose.maintenance").rename_project_command({ args = { p, new }, bang = false })
        end
      end)
    end, true),
    "Rename"
  )
  map(
    "D",
    on_row(function(p)
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
    on_row(function(p, r)
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

return M

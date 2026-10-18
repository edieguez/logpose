--- `:Logpose projects`: the manager screen. One row per project with what needs attention;
--- <Tab> expands a project, and keys switch, add, rename, merge, archive and restore projects.
local config = require("logpose.config")
local project = require("logpose.project")
local ui = require("logpose.util.ui")
local summary = require("logpose.projects.summary")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.projects")

M.HELP = {
  "Projects",
  "",
  "  <CR>   switch to the project (on a detail line: open it)",
  "  <Tab>  show / hide what's going on in it",
  "  b      its board                 n  its project page",
  "  t      its open tasks            f  its notes",
  "  a      add a project             p  link a repo folder",
  "  e      edit name, description, repo folders, colour",
  "  R      rename                    M  merge into another project",
  "  D      archive (hide)            U  restore an archived one",
  "  A      show / hide archived      c  back to auto-detect",
  "  r      refresh                   q  close",
}

--- The manager screen, as lines of chunks.
---@param root string
---@param opts? { show_archived?: boolean, expanded?: table<string, boolean>, today?: string }
---@return logpose.ProjectsLine[]
function M.build(root, opts)
  opts = opts or {}
  local list = summary.stats(root, opts.today)
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
      for _, c in ipairs(summary.summary(e)) do
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
    for _, c in ipairs(summary.summary(e)) do
      table.insert(chunks, faded and { c[1], "Comment" } or c)
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    if e.last then
      table.insert(chunks, { string.rep(" ", sum_width - w + 3) .. e.last, "Comment" })
    end
    add(chunks, { project = e.name, archived = e.archived })
    if (opts.expanded or {})[e.name] then
      for _, d in ipairs(summary.details(e, "        ")) do
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
function M.ask(prompt, default, fn)
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
      project.switch_to(p)
      if vim.api.nvim_get_current_buf() == buf then
        render(buf, root, p) -- the board is off: stay here
      end
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
    M.ask("New project: ", nil, function(p, typed)
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
    "e",
    on_project(function(p)
      -- the page holds the project's name, description, repo folders and colour
      local path = require("logpose.notes.topic").project_page(root, p, { open = false })
      require("logpose.edit").open(path, {
        root = root,
        on_save = function()
          render(buf, root, p)
        end,
      })
    end, true),
    "Edit name, description, repo folders, colour"
  )
  map(
    "R",
    on_project(function(p)
      M.ask(("Rename %s to: "):format(p), p, function(new)
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

return M

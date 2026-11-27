--- Tasks: task files under `dirs.tasks`, shown on the board. `:Logpose capture [text]` creates
--- one, `:Logpose done` finishes the one you're in. (Checkboxes in notes are to-dos: `todos.lua`.)
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local ui = require("logpose.util.ui")

local M = {}

--- The task file captured last in this session (`:Logpose edit last` opens it).
---@type string?
M.last = nil

--- Why a project was chosen, in words (for the capture prompt and confirmation).
local SOURCES = {
  explicit = "pinned",
  path = "projects.paths",
  page = "its folder",
  git = "this repo",
}

--- "acme (this repo)", "thesis", or "no project".
---@param project? string
---@param source? string
---@return string
function M.describe_project(project, source)
  if not project then
    return "no project"
  end
  local why = source and SOURCES[source]
  return why and ("%s (%s)"):format(project, why) or project
end

--- People in a captured text: `@name` assigns the task (the last one wins; `@none`: nobody) and
--- `for:name` adds a stakeholder. Names come back as the journal writes them (a page's name).
---@param text string
---@param root? string
---@return string rest, string? assignee, string[] stakeholders
function M.take_people(text, root)
  local rest, assignee, stakeholders = require("logpose.taskfile").take_people(text)
  if not assignee and #stakeholders == 0 then
    return rest, nil, stakeholders
  end
  local people = require("logpose.people")
  local known = people.known(root)
  local out, seen = {}, {}
  for _, name in ipairs(stakeholders) do
    name = people.canonical(name, known)
    if not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  return rest, assignee and people.canonical(assignee, known) or nil, out
end

--- Capture `text` as a task file in `tasks.capture_status` (files mode). A `+name` in the text
--- picks the project; otherwise `project` (the detected one) is used. `@name` and `for:name`:
--- see `M.take_people`.
---@param text string
---@param root string
---@param project? string
---@param open? boolean open the new file to add context
---@param source? string how `project` was found (see `project.resolve`)
---@return string path
function M.capture_file(text, root, project, open, source)
  local taskfile = require("logpose.taskfile")
  local rest, assignee, stakeholders = M.take_people(text, root)
  local title, tags, due, explicit, unread = taskfile.from_text(rest)
  if explicit ~= nil then
    project, source = explicit or nil, nil
  end
  tags = vim.tbl_filter(function(t)
    return t ~= project
  end, tags)
  local status = config.get().tasks.capture_status
  local path, cursor = taskfile.create(root, {
    title = title,
    project = project,
    assignee = assignee,
    stakeholders = stakeholders,
    tags = tags,
    due = due,
  })
  M.last = path
  if open then
    vim.cmd.edit(vim.fn.fnameescape(path))
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
  local shown = vim.fn.strcharlen(title) > 40 and (vim.fn.strcharpart(title, 0, 39) .. "…") or title
  require("logpose.util.ui").notify(
    ("logpose: captured “%s” → %s · %s%s%s"):format(
      shown,
      M.describe_project(project, source),
      taskfile.label(status),
      assignee and (" · for " .. assignee) or "",
      open and "" or " · :Logpose edit last to change"
    ),
    vim.log.levels.INFO
  )
  local warning = taskfile.due_warning(unread)
  if warning then
    require("logpose.util.ui").notify(warning, vim.log.levels.WARN)
  end
  return path
end

--- Completion for task text (capture, the board's `a`): `+project`, `#tag`, `due:`, `@person`,
--- `for:person`.
---@param arglead string
---@param root? string
---@return string[]
function M.complete_text(arglead, root)
  local ok, r = pcall(function()
    return root or config.root()
  end)
  if not ok or not r then
    return {}
  end
  local out = {}
  local function add(word)
    if vim.startswith(word:lower(), arglead:lower()) then
      table.insert(out, word)
    end
  end
  if arglead:sub(1, 1) == "+" then
    for _, name in ipairs(require("logpose.project").known(r)) do
      add("+" .. name)
    end
    add("+none")
  elseif arglead:sub(1, 1) == "#" then
    local index = require("logpose.index")
    for _, c in ipairs(index.tag_counts(index.build(r))) do
      add("#" .. c.tag)
    end
  elseif arglead:sub(1, 1) == "@" or arglead:lower():match("^for:") then
    -- people by a handle (a name with spaces wouldn't stay one word): their page's, else the
    -- first of their other handles starting with what's typed
    local prefix = arglead:sub(1, 1) == "@" and "@" or arglead:sub(1, 4)
    local typed = require("logpose.people").plain(arglead:sub(#prefix + 1))
    for _, p in ipairs(require("logpose.people").known(r)) do
      local handle = vim.startswith(p.slug, typed) and p.slug or nil
      if not handle then
        local slugs = vim.tbl_keys(p.slugs or {})
        table.sort(slugs)
        for _, s in ipairs(slugs) do
          if vim.startswith(s, typed) then
            handle = s
            break
          end
        end
      end
      if handle then
        table.insert(out, prefix .. handle)
      end
    end
    if prefix == "@" and vim.startswith("none", arglead:sub(2):lower()) then
      table.insert(out, "@none")
    end
  elseif vim.startswith("due:", arglead:lower()) or arglead:lower():match("^due:") then
    for _, w in ipairs({ "today", "tomorrow", "mon", "tue", "wed", "thu", "fri", "+1w", "+2w" }) do
      add("due:" .. w)
    end
  end
  return out
end

--- `:Logpose capture` completion.
---@param arglead string
function M.complete(arglead, _)
  return M.complete_text(arglead)
end

--- `:Logpose capture [text]`: a new task. With text, it's created at once (`+name` picks the
--- project, `#tag` and `due:` work too); without, the new-task form opens.
---@param opts logpose.CommandOpts
function M.capture_command(opts)
  local text = vim.trim(table.concat(opts.args, " "))
  config.with_root(ui.safely(function(root)
    local project, source = require("logpose.project").resolve(root)
    if text ~= "" then
      M.capture_file(text, root, project, opts.bang, source)
      return
    end
    require("logpose.edit").open_new(root, { project = project, status = config.get().tasks.capture_status })
  end))
end

--- Ask which project to move to: known projects, a new one, or none.
---@param root string
---@param current? string
---@param fn fun(project?: string)
function M.choose_project(root, current, fn)
  local project = require("logpose.project")
  local items = {}
  for _, name in ipairs(project.known(root)) do
    if name ~= current then
      local title = project.title(root, name)
      table.insert(items, { label = title ~= name and ("%s  (%s)"):format(name, title) or name, value = name })
    end
  end
  table.insert(items, { label = "New project…", new = true })
  if current then
    table.insert(items, { label = "No project", none = true })
  end
  vim.ui.select(
    items,
    {
      prompt = "Move to project",
      format_item = function(it)
        return it.label
      end,
    },
    ui.safely(function(choice)
      if not choice then
        return
      end
      if choice.none then
        return fn(nil)
      end
      if not choice.new then
        return fn(choice.value)
      end
      vim.ui.input(
        { prompt = "New project: " },
        ui.safely(function(input)
          local slug = input and project.normalize(vim.trim(input))
          if slug then
            fn(slug)
          end
        end)
      )
    end)
  )
end

--- Ask who does a task: you (`me`), the people you know (the project's first), someone new, or
--- nobody. `fn` gets the name as the journal writes it, or nil for nobody.
---@param root string
---@param project? string  its people come first
---@param current? string  the task's assignee now (not offered again)
---@param fn fun(assignee?: string)
function M.choose_assignee(root, project, current, fn)
  local people = require("logpose.people")
  local known = people.known(root)
  local cur = current and people.find(known, current)
  local items = {}
  local me = config.get().me
  local my_name = type(me) == "string" and vim.trim((me:gsub("^@", ""))) ~= "" and people.canonical(me, known) or nil
  local mine = my_name and people.find(known, my_name)
  if my_name and not (cur and cur == mine) then
    table.insert(items, { label = ("Me (%s)"):format(my_name), value = my_name })
  end
  for _, p in ipairs(people.match(known, "", project)) do
    if p ~= cur and p ~= mine then
      local about = people.describe(p)
      table.insert(items, { label = about ~= "" and ("%s  (%s)"):format(p.name, about) or p.name, value = p.name })
    end
  end
  table.insert(items, { label = "Someone new…", new = true })
  if current then
    table.insert(items, { label = "Nobody", none = true })
  end
  vim.ui.select(
    items,
    {
      prompt = "Assign to",
      format_item = function(it)
        return it.label
      end,
    },
    ui.safely(function(choice)
      if not choice then
        return
      end
      if choice.none then
        return fn(nil)
      end
      if not choice.new then
        return fn(choice.value)
      end
      vim.ui.input(
        { prompt = "Assign to: ", completion = "customlist,v:lua.LogposeCompletePeople" },
        ui.safely(function(input)
          input = input and vim.trim((input:gsub("^@", ""))) or ""
          if input ~= "" then
            fn(people.canonical(input, known))
          end
        end)
      )
    end)
  )
end

--- `:Logpose done`: move the task you're in (its task file) to Done.
---@param _ logpose.CommandOpts
function M.done_command(_)
  config.with_root(ui.safely(function(root)
    local name = vim.api.nvim_buf_get_name(0)
    local path = name ~= "" and fs.in_root(name, root) or nil
    local taskfile = require("logpose.taskfile")
    if not path or not taskfile.is_task_file(path, root) then
      error("logpose: :Logpose done works in a task file (a to-do is checked off with :Logpose check)", 0)
    end
    local done = config.get().board.done
    if taskfile.set_status(path, done) then
      ui.notify("logpose: moved to " .. taskfile.label(done), vim.log.levels.INFO)
    else
      ui.notify("logpose: already " .. taskfile.label(done), vim.log.levels.INFO)
    end
  end))
end

return M

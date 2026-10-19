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

--- Capture `text` as a task file in `tasks.capture_status` (files mode). A `+name` in the text
--- picks the project; otherwise `project` (the detected one) is used.
---@param text string
---@param root string
---@param project? string
---@param open? boolean open the new file to add context
---@param source? string how `project` was found (see `project.resolve`)
---@return string path
function M.capture_file(text, root, project, open, source)
  local taskfile = require("logpose.taskfile")
  local title, tags, due, explicit = taskfile.from_text(text)
  if explicit ~= nil then
    project, source = explicit or nil, nil
  end
  tags = vim.tbl_filter(function(t)
    return t ~= project
  end, tags)
  local status = config.get().tasks.capture_status
  local path, cursor = taskfile.create(root, { title = title, project = project, tags = tags, due = due })
  M.last = path
  if open then
    vim.cmd.edit(vim.fn.fnameescape(path))
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
  local shown = vim.fn.strcharlen(title) > 40 and (vim.fn.strcharpart(title, 0, 39) .. "…") or title
  require("logpose.util.ui").notify(
    ("logpose: captured “%s” → %s · %s%s"):format(
      shown,
      M.describe_project(project, source),
      taskfile.label(status),
      open and "" or " · :Logpose edit last to change"
    ),
    vim.log.levels.INFO
  )
  return path
end

--- Completion for task text (capture, the board's `a`): `+project`, `#tag`, `due:`.
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

--- `:Logpose done`: move the task you're in (its task file) to Done.
---@param _ logpose.CommandOpts
function M.done_command(_)
  config.with_root(ui.safely(function(root)
    local path = vim.api.nvim_buf_get_name(0)
    local taskfile = require("logpose.taskfile")
    if path == "" or not taskfile.is_task_file(fs.normalize(path), root) then
      error("logpose: :Logpose done works in a task file (a to-do is checked off with :Logpose check)", 0)
    end
    local done = config.get().board.done
    if taskfile.set_status(fs.normalize(path), done) then
      ui.notify("logpose: moved to " .. taskfile.label(done), vim.log.levels.INFO)
    else
      ui.notify("logpose: already " .. taskfile.label(done), vim.log.levels.INFO)
    end
  end))
end

return M

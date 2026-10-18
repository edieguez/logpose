--- Kanban flow: `:Logpose capture [text]` and `:Logpose done` (current line or visual range).
local archive = require("logpose.archive")
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local link = require("logpose.link")
local markdown = require("logpose.markdown")
local ui = require("logpose.util.ui")

local M = {}

--- Parse a markdown task line.
---@param line string
---@return { indent: string, checked: boolean, text: string }?
function M.parse_task(line)
  local indent, mark, rest = line:match("^(%s*)[-*+]%s+%[([ xX])%]%s?(.*)$")
  if not indent then
    return nil
  end
  return { indent = indent, checked = mark ~= " ", text = rest }
end

--- Add `item` to the `## iso` section of a list of lines (section created in date order).
---@param lines string[]
---@param iso string
---@param item string
---@return string[]? new_lines nil when the item is already in that section
function M.add_to_day(lines, iso, item)
  local doc = markdown.parse(table.concat(lines, "\n") .. "\n")
  local order = config.get().section_order
  if order == "auto" then
    order = markdown.detect_order(doc) or "oldest_first"
  end
  if archive.merge_section(doc, iso, { item }, order) == "skipped" then
    return nil
  end
  local out = vim.split(markdown.render(doc), "\n", { plain = true })
  if out[#out] == "" then
    table.remove(out)
  end
  return out
end

--- Append `items` under today's section of the file at `path` (created with `title` if missing).
---@param path string
---@param title string
---@param items string[]
---@return "file"|"buffer"|nil changed, integer added
local function add_items(path, title, items)
  if not fs.exists(path) then
    local ok, err = fs.write_file(path, title .. "\n", { tidy = true })
    if not ok then
      error(err, 0)
    end
  end
  local today = date.today()
  local added = 0
  local ok, err, changed = fs.update_lines(path, function(lines)
    local current, touched = lines, false
    for _, item in ipairs(items) do
      local new = M.add_to_day(current, today, item)
      if new then
        current, touched = new, true
        added = added + 1
      end
    end
    return touched and current or nil
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
  return changed, added
end

--- Log `items` (already formatted lines) under today's section in DONE.md.
---@param root string
---@param items string[]
---@return "file"|"buffer"|nil changed, integer added
function M.log_done(root, items)
  return add_items(config.path("done", root), "# DONE", items)
end

--- Capture `text` into INBOX under today's date, tagged with the active project (or the one
--- named in the text with `+name`).
---@param text string
---@param root string
---@param project? string
function M.capture(text, root, project)
  local explicit
  text, explicit = require("logpose.taskfile").take_project(text)
  if explicit ~= nil then
    project = explicit or nil
  end
  local item = "- [ ] " .. text
  if project and not text:find("#" .. project, 1, true) then
    item = item .. " #" .. project
  end
  local changed, added = add_items(config.path("inbox", root), "# INBOX", { item })
  if added == 0 then
    require("logpose.util.ui").notify("logpose: already in today's INBOX", vim.log.levels.INFO)
  elseif changed == "buffer" then
    require("logpose.util.ui").notify("logpose: captured to the INBOX buffer (unsaved)", vim.log.levels.INFO)
  else
    require("logpose.util.ui").notify("logpose: captured to INBOX", vim.log.levels.INFO)
  end
end

---@param path string
---@param key string
---@param root string
local function same_file(path, key, root)
  local a = vim.uv.fs_realpath(path) or fs.normalize(path)
  local target = config.path(key, root)
  local b = vim.uv.fs_realpath(target) or fs.normalize(target)
  return a == b
end

--- Mark tasks in lines `line1..line2` of the current buffer as done.
--- INBOX: moved to DONE. Other journal notes: checked off in place and logged in DONE with a link.
---@param root string
---@param line1 integer
---@param line2 integer
function M.done(root, line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    error("logpose: :Logpose done works on a journal file", 0)
  end
  local abs = fs.normalize(path)
  local real_root = fs.normalize(root)
  if not vim.startswith(vim.uv.fs_realpath(abs) or abs, (vim.uv.fs_realpath(real_root) or real_root) .. "/") then
    error("logpose: not a journal file (outside " .. vim.fn.fnamemodify(root, ":~") .. ")", 0)
  end
  if same_file(abs, "done", root) then
    require("logpose.util.ui").notify("logpose: already in DONE", vim.log.levels.INFO)
    return
  end

  local taskfile = require("logpose.taskfile")
  if
    taskfile.is_task_file(abs, root)
    and not M.parse_task(vim.api.nvim_buf_get_lines(buf, line1 - 1, line1, false)[1] or "")
  then
    -- In a task file (not on one of its checklist items): the task itself is done.
    local done = config.get().board.done
    if taskfile.set_status(abs, done) then
      require("logpose.util.ui").notify("logpose: moved to " .. taskfile.label(done), vim.log.levels.INFO)
    else
      require("logpose.util.ui").notify("logpose: already " .. taskfile.label(done), vim.log.levels.INFO)
    end
    return
  end

  local from_inbox = same_file(abs, "inbox", root)
  -- With task files, a checkbox outside INBOX is just checked off (no DONE.md log).
  local log = from_inbox or config.get().tasks.mode == "inbox"
  local was_modified = vim.bo[buf].modified
  local lines = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, false)
  local done_path = config.path("done", root)
  local items, rows, skipped, already = {}, {}, 0, 0
  for i, line in ipairs(lines) do
    local task = M.parse_task(line)
    if not task then
      skipped = skipped + 1
    elseif task.checked and not from_inbox then
      already = already + 1
    else
      local item = "- [x] " .. task.text
      if not from_inbox and log then
        local label = vim.fn.fnamemodify(abs, ":t:r")
        item = item .. " (" .. link.make(done_path, abs, label, root) .. ")"
      end
      table.insert(items, item)
      table.insert(rows, line1 + i - 1)
    end
  end

  if #items > 0 then
    if log then
      add_items(done_path, "# DONE", items)
    end
    -- Edit the current buffer through the API so `u` undoes it.
    for j = #rows, 1, -1 do
      local row = rows[j]
      if from_inbox then
        vim.api.nvim_buf_set_lines(buf, row - 1, row, false, {})
      else
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
        local checked = line:gsub("%[ %]", "[x]", 1)
        vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { checked })
      end
    end
    -- Keep disk consistent with DONE (unless the user already had unsaved edits here).
    if not was_modified then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
    end
  end

  local parts = {}
  if #items > 0 then
    table.insert(parts, ("%d task%s done"):format(#items, #items == 1 and "" or "s"))
  end
  if already > 0 then
    table.insert(parts, ("%d already checked"):format(already))
  end
  if skipped > 0 then
    table.insert(parts, ("skipped %d non-task line%s"):format(skipped, skipped == 1 and "" or "s"))
  end
  require("logpose.util.ui").notify("logpose: " .. table.concat(parts, ", "), vim.log.levels.INFO)
end

--- The task file captured last in this session (`:Logpose edit last` opens it).
---@type string?
M.last = nil

--- Why a project was chosen, in words (for the capture prompt and confirmation).
local SOURCES = {
  explicit = "pinned",
  path = "projects.paths",
  page = "its folder",
  git = "this repo",
  board = "this board",
  lane = "this row",
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

--- Completion for `vim.ui.input` prompts that take task text ('customlist' signature).
---@param arglead string
---@param cmdline string
---@return string[]
function M.complete_input(arglead, cmdline, _)
  -- input() hands over the whole line; complete its last word
  local word = (cmdline or arglead):match("(%S*)$") or ""
  local before = (cmdline or arglead):sub(1, #(cmdline or arglead) - #word)
  return vim.tbl_map(function(w)
    return before .. w
  end, M.complete_text(word))
end

---@param opts logpose.CommandOpts
function M.capture_command(opts)
  local text = vim.trim(table.concat(opts.args, " "))
  local files = config.get().tasks.mode == "files"
  config.with_root(ui.safely(function(root)
    local project, source = require("logpose.project").resolve(root)
    local function capture(t)
      if files then
        M.capture_file(t, root, project, opts.bang, source)
      else
        M.capture(t, root, project)
      end
    end
    if text ~= "" then
      capture(text)
      return
    end
    local prompt = ("Capture → %s (+name for another): "):format(M.describe_project(project, source))
    vim.ui.input(
      { prompt = prompt, completion = "customlist,v:lua.require'logpose.tasks'.complete_input" },
      ui.safely(function(input)
        input = input and vim.trim(input) or ""
        if input == "" then
          require("logpose.util.ui").notify("logpose: cancelled (empty input)", vim.log.levels.INFO)
          return
        end
        capture(input)
      end)
    )
  end))
end

---@param opts logpose.CommandOpts
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

--- `:Logpose move [project|none]` in a task file: move the task to another project.
---@param opts logpose.CommandOpts
function M.move_command(opts)
  local root = config.root()
  local path = vim.api.nvim_buf_get_name(0)
  local taskfile = require("logpose.taskfile")
  if not taskfile.is_task_file(path, root) then
    error("logpose: :Logpose move works in a task file (on the board, press m)", 0)
  end
  local function apply(target)
    if taskfile.set_project(path, target) then
      vim.cmd("silent! checktime")
      require("logpose.project").changed()
      ui.notify(("logpose: moved to %s"):format(target or "no project"), vim.log.levels.INFO)
    end
  end
  local arg = vim.trim(table.concat(opts.args, " "))
  if arg == "none" then
    return apply(nil)
  elseif arg ~= "" then
    local slug = require("logpose.project").normalize(arg)
    if not slug then
      error(("logpose: invalid project name %q"):format(arg), 0)
    end
    return apply(slug)
  end
  local fm = require("logpose.index").frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  M.choose_project(root, type(fm.project) == "string" and fm.project ~= "" and fm.project or nil, apply)
end

function M.complete_move(_, args)
  if #args > 0 then
    return {}
  end
  local items = require("logpose.project").known(config.resolve_root())
  table.insert(items, "none")
  return items
end

function M.done_command(opts)
  local line1, line2 = opts.line1, opts.line2
  if opts.range == 0 or line1 == 0 then
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end
  local root = config.root()
  M.done(root, line1, line2)
end

return M

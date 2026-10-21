--- `:Logpose <subcommand>` dispatcher, completion and <Plug> mappings.
local M = {}

---@class logpose.CommandOpts
---@field args string[]   arguments after the subcommand
---@field bang boolean
---@field range integer   0, 1 or 2 (as in nvim_create_user_command)
---@field line1 integer
---@field line2 integer

---@class logpose.Subcommand
---@field impl fun(opts: logpose.CommandOpts)
---@field complete? fun(arglead: string, args: string[]): string[]
---@field desc? string
---@field plug? false|string[]  modes for a <Plug>(logpose-<name>) mapping; false to skip (default {"n"})

---@type table<string, logpose.Subcommand>
M.subcommands = {}

--- Register a subcommand (features call this from their modules).
---@param name string
---@param spec logpose.Subcommand
function M.register(name, spec)
  M.subcommands[name] = spec
  if spec.plug ~= false then
    local lhs = ("<Plug>(logpose-%s)"):format(name)
    vim.keymap.set(spec.plug or { "n" }, lhs, function()
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        vim.cmd(("normal! %s"):format(vim.api.nvim_replace_termcodes("<Esc>", true, false, true)))
        vim.cmd(("'<,'>Logpose %s"):format(name))
      else
        vim.cmd(("Logpose %s"):format(name))
      end
    end, { desc = spec.desc or ("logpose: " .. name), silent = true })
  end
end

---@return string[]
function M.names()
  local names = vim.tbl_keys(M.subcommands)
  table.sort(names)
  return names
end

--- Handler for the user command.
---@param cmd table opts from nvim_create_user_command
function M.dispatch(cmd)
  local fargs = cmd.fargs or {}
  local name = fargs[1]
  -- `:Logpose archive!` reads better than `:Logpose! archive`; accept both.
  local sub_bang = false
  if name and name:sub(-1) == "!" then
    name, sub_bang = name:sub(1, -2), true
  end
  local names = M.names()
  if not name then
    -- No subcommand: pick one from the menu.
    local ok, err = pcall(require("logpose.menu").open)
    if not ok then
      require("logpose.util.ui").notify("logpose: " .. tostring(err), vim.log.levels.ERROR)
    end
    return
  end
  local sub = M.subcommands[name]
  if not sub then
    local valid = #names > 0 and table.concat(names, ", ") or "(none yet)"
    require("logpose.util.ui").notify(
      ("logpose: unknown subcommand %q. Valid: %s"):format(name, valid),
      vim.log.levels.ERROR
    )
    return
  end
  local args = vim.list_slice(fargs, 2)
  local ok, err = pcall(sub.impl, {
    args = args,
    bang = cmd.bang or sub_bang,
    range = cmd.range or 0,
    line1 = cmd.line1 or 0,
    line2 = cmd.line2 or 0,
  })
  if name ~= "stats" then
    pcall(function()
      require("logpose.telemetry").record(name, args, ok)
    end)
  end
  if not ok then
    local msg = type(err) == "string" and err or vim.inspect(err)
    if not msg:find("^logpose:") then
      msg = "logpose: " .. msg
    end
    require("logpose.util.ui").notify(msg, vim.log.levels.ERROR)
  end
end

--- Completion for the user command.
---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  -- Drop the command name (and any range/bang) and split the rest.
  local rest = cmdline:gsub("^.-Logpose!?%s*", "")
  local words = vim.split(rest, "%s+", { trimempty = true })
  if arglead ~= "" then
    table.remove(words) -- the word being completed
  end
  local function filter(items)
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, items)
  end
  if #words == 0 then
    return filter(M.names())
  end
  local sub = M.subcommands[words[1]]
  if sub and sub.complete then
    return filter(sub.complete(arglead, vim.list_slice(words, 2)))
  end
  return {}
end

--- Built-in subcommands: name -> module exposing `command(opts)` (or `fn`) and optionally
--- `complete(arglead, args)`. Modules load only when the subcommand runs or completes.
M.builtin = {
  init = { module = "logpose.onboard", desc = "logpose: choose or create the journal" },
  actions = { module = "logpose.actions", desc = "logpose: meeting action items (to-dos in meeting notes)" },
  archive = { module = "logpose.archive", desc = "logpose: move done tasks from past weeks or sprints off the board" },
  daily = { module = "logpose.notes.daily", desc = "logpose: open the daily note" },
  meeting = { module = "logpose.notes.meeting", desc = "logpose: new meeting note" },
  project = { module = "logpose.project", desc = "logpose: set the active project" },
  projects = { module = "logpose.projects", complete = false, desc = "logpose: manage projects" },
  standup = {
    module = "logpose.standup",
    complete = false,
    desc = "logpose: Yesterday / Today / Blockers for the standup",
  },
  note = { module = "logpose.notes.topic", fn = "note_command", complete = false, desc = "logpose: topic note" },
  notes = { module = "logpose.notes.browse", desc = "logpose: browse notes, by type or project" },
  people = { module = "logpose.people.screen", complete = false, desc = "logpose: people you work with" },
  person = {
    module = "logpose.people.screen",
    fn = "person_command",
    complete_fn = "complete_person",
    desc = "logpose: open or add a person's page",
  },
  ["project-page"] = {
    module = "logpose.notes.topic",
    fn = "project_page_command",
    complete_fn = "complete_projects",
    desc = "logpose: project page",
  },
  backlinks = { module = "logpose.links", fn = "backlinks_command", complete = false, desc = "logpose: backlinks" },
  links = { module = "logpose.links", fn = "links_command", complete = false, desc = "logpose: outgoing links" },
  view = { module = "logpose.views", desc = "logpose: run a saved search" },
  report = { module = "logpose.report", desc = "logpose: week or sprint report" },
  ticket = { module = "logpose.tickets", complete = false, desc = "logpose: notes mentioning a ticket" },
  stats = { module = "logpose.telemetry", complete = false, desc = "logpose: local usage stats" },
  ["rename-tag"] = {
    module = "logpose.maintenance",
    fn = "rename_tag_command",
    complete_fn = "complete_tags",
    desc = "logpose: rename a tag everywhere",
  },
  ["rename-person"] = {
    module = "logpose.people.rename",
    desc = "logpose: rename a person everywhere",
  },
  ["rename-project"] = {
    module = "logpose.maintenance",
    fn = "rename_project_command",
    complete_fn = "complete_projects",
    desc = "logpose: rename a project everywhere",
  },
  ["merge-project"] = {
    module = "logpose.maintenance",
    fn = "merge_project_command",
    complete_fn = "complete_projects",
    desc = "logpose: merge one project into another",
  },
  edit = { module = "logpose.edit", desc = "logpose: edit the details (frontmatter) of this note or task" },
  capture = { module = "logpose.tasks", fn = "capture_command", desc = "logpose: new task (on the board, in Backlog)" },
  find = {
    module = "logpose.search",
    fn = "find_command",
    desc = "logpose: search notes, tasks, to-dos, tags, projects, people",
  },
  grep = { module = "logpose.search", fn = "grep_command", complete = false, desc = "logpose: grep the journal" },
  done = {
    module = "logpose.tasks",
    fn = "done_command",
    complete = false,
    desc = "logpose: move the task you're in to Done",
  },
  check = {
    module = "logpose.todos",
    fn = "check_command",
    complete = false,
    desc = "logpose: check off the to-do on this line (or the selected ones)",
    plug = { "n", "x" },
  },
  promote = {
    module = "logpose.todos",
    fn = "promote_command",
    complete = false,
    desc = "logpose: promote: a to-do becomes a task; a task's write-up becomes a note",
    plug = { "n", "x" },
  },
  board = { module = "logpose.board", desc = "logpose: Kanban board of tasks" },
  today = { module = "logpose.today", complete = false, desc = "logpose: today at a glance: tasks and notes" },
}

--- Create `:Logpose` and register built-in subcommands. Called once from plugin/logpose.lua.
function M.create()
  for name, spec in pairs(M.builtin) do
    M.register(name, {
      desc = spec.desc,
      plug = spec.plug,
      impl = function(opts)
        require(spec.module)[spec.fn or "command"](opts)
      end,
      complete = function(arglead, args)
        if spec.complete == false then
          return {}
        end
        local mod = require(spec.module)
        local fn = mod[spec.complete_fn or "complete"]
        return fn and fn(arglead, args) or {}
      end,
    })
  end
  vim.api.nvim_create_user_command("Logpose", M.dispatch, {
    nargs = "*",
    bang = true,
    range = true,
    complete = M.complete,
    desc = "logpose.nvim journal commands",
  })
end

return M

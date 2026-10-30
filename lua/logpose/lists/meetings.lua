--- `:Logpose meetings [filter]`: every meeting note, grouped by week (or type, project, series),
--- with who was there, its open action items and the tasks it led to. Moving a meeting to another
--- type or project changes the note (another project moves it to that project's folder).
local common = require("logpose.lists.common")
local lists = require("logpose.lists")
local text = require("logpose.util.text")

local M = {}

M.name = "meetings"
M.title = "Meetings"
M.empty = "No meetings yet: a starts one"
M.footer = "<CR> open · <Tab> details · / filter · g group · m move · a new · ? help"
M.noun = "meetings"
M.one = "meeting"
M.help = {
  { "a", "a new meeting (of this group's type or project)" },
}

--- The meeting types' labels.
---@return table<string, string>
local function type_labels()
  local out = {}
  for _, t in ipairs(require("logpose.notes.meeting").types()) do
    out[t.key] = t.spec.label or t.key
  end
  return out
end

---@param s logpose.ListState
---@return logpose.ListEntry[]
function M.collect(s)
  local items = require("logpose.index").build(s.root)
  local info = common.note_info(s.root, items)
  local out = {}
  for _, it in ipairs(items) do
    if it.kind == "note" and it.file_type == "meeting" then
      local fm = it.fields or {}
      local attendees = common.list(fm.attendees)
      if #attendees == 0 and type(fm.with) == "string" and fm.with ~= "" then
        attendees = { fm.with }
      end
      table.insert(out, {
        key = it.file,
        file = it.file,
        item = it,
        when = it.date or "",
        attendees = attendees,
        info = info[it.file] or { open = {}, checked = 0, tasks = {} },
      })
    end
  end
  return out
end

local function save(s, e, changed)
  return require("logpose.edit.save").note(s.root, e.file, "meeting", changed)
end

M.groupings = {
  {
    key = "week",
    label = "week",
    descending = true,
    none = "No date",
    of = function(e)
      return common.week_group(e.item.date)
    end,
  },
  {
    key = "type",
    label = "type",
    none = "No type",
    of = function(e)
      local t = e.item.type
      if not t then
        return {}
      end
      return { { key = t, label = type_labels()[t] or t } }
    end,
    targets = function()
      local out = {}
      for _, t in ipairs(require("logpose.notes.meeting").types()) do
        table.insert(out, { key = t.key, label = t.spec.label or t.key })
      end
      return out
    end,
    move = function(s, e, _, to)
      return save(s, e, { type = to ~= "" and to or "" })
    end,
  },
  {
    key = "project",
    label = "project",
    none = "No project",
    ask = "New project: ",
    of = function(e, s)
      return common.project_group(s, e.item.project)
    end,
    targets = common.project_targets,
    move = function(s, e, _, to)
      local project = to ~= "" and require("logpose.project").normalize(to) or ""
      return save(s, e, { project = project or "" })
    end,
  },
  {
    key = "series",
    label = "series",
    none = "Not in a series",
    of = function(e)
      local series = e.item.series
      return series and { { key = series, label = series } } or {}
    end,
  },
}

M.sorts = {
  { label = "newest first", cmp = common.newest },
  { label = "oldest first", cmp = common.oldest },
  { label = "by title", cmp = common.by_title },
}

M.columns = {
  { key = "day", max = 12, hl = "LogposeListDate" },
  { key = "type", max = 18, min = 6, hl = "LogposeListMeta" },
  { key = "title", flex = true, max = 56 },
  { key = "attendees", max = 48, min = 10, hl = "LogposeListPeople" },
  { key = "activity", max = 30 },
  { key = "project", max = 24 },
}

---@param ctx table
function M.layout(ctx)
  ctx.labels = type_labels()
end

---@param e logpose.ListEntry
---@param ctx table
---@return table<string, string|table[]>
function M.cells(e, ctx)
  local it = e.item
  local label
  if ctx.group ~= "type" then
    label = ctx.labels[it.type] or it.type or ""
    if text.plain(label) == text.plain(it.title or "") then
      label = nil -- "Sprint planning  Sprint planning": once is enough
    end
  end
  local activity = {}
  if #e.info.open > 0 then
    table.insert(activity, { ("☐ %d open"):format(#e.info.open), "LogposeListTodos" })
  end
  if #e.info.tasks > 0 then
    table.insert(
      activity,
      { ("→ %d task%s"):format(#e.info.tasks, #e.info.tasks == 1 and "" or "s"), "LogposeListTasks" }
    )
  end
  return {
    day = common.day(it.date),
    type = label,
    title = it.title or "",
    attendees = #e.attendees > 0 and common.people(e.attendees) or nil,
    activity = common.joined(activity),
    project = ctx.all_projects and ctx.group ~= "project" and it.project and {
      { "◆ " .. it.project, ctx.hl(it.project) },
    } or nil,
  }
end

---@param e logpose.ListEntry
---@return table[]
function M.details(e)
  local out = {}
  if #e.attendees > 0 then
    table.insert(
      out,
      { chunks = { { "with ", "LogposeListMeta" }, { table.concat(e.attendees, ", "), "LogposeListPeople" } } }
    )
  end
  for _, t in ipairs(e.info.open) do
    table.insert(out, { chunks = { { "☐ ", "LogposeListTodos" }, { t.text } }, file = t.file, lnum = t.lnum })
  end
  if e.info.checked > 0 then
    table.insert(out, { chunks = { { ("☑ %d done"):format(e.info.checked), "LogposeListMeta" } } })
  end
  for _, t in ipairs(e.info.tasks) do
    local label = t.status and require("logpose.taskfile").label(t.status) or ""
    table.insert(out, {
      chunks = {
        { "▣ ", "LogposeListTasks" },
        { t.title },
        { label ~= "" and ("  " .. label) or "", "LogposeListMeta" },
      },
      file = t.file,
    })
  end
  return out
end

function M.open(e)
  vim.cmd.edit(vim.fn.fnameescape(e.file))
end

function M.edit(e, s, done)
  require("logpose.edit").open(e.file, {
    root = s.root,
    on_save = function(path)
      done(path)
    end,
  })
end

--- A new meeting, of this group's type or project.
function M.add(s, group)
  local defaults = { project = s.project }
  local by = s.view.groupings[s.group].key
  if by == "type" and group and group ~= "" then
    defaults.type = group
  elseif by == "project" then
    defaults.project = group ~= "" and group or nil
  end
  require("logpose.edit").open_new_note(s.root, "meeting", defaults)
end

M.command = lists.command_for(M)

---@param arglead string
function M.complete(arglead, _)
  return require("logpose.search").complete(arglead, { "meetings" })
end

return M

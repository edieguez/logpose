--- `:Logpose notes [filter]`: topic notes and project pages (daily notes and meetings with
--- `type:daily` or `type:meeting` in the filter; meetings have `:Logpose meetings`), grouped by
--- type, project, tag or month. Moving a note to another project or tag changes the note.
local common = require("logpose.lists.common")
local lists = require("logpose.lists")

local M = {}

M.name = "notes"
M.title = "Notes"
M.empty = "No notes yet: a writes one"
M.footer = "<CR> open · <Tab> details · / filter · g group · m move · a new · ? help"
M.noun = "notes"
M.one = "note"
M.help = {
  { "a", "a new topic note (in this group's project or tag)" },
  { "d  b", "today's daily note · the board" },
  { "type:daily", "in the filter: daily notes too (type:meeting: meetings)" },
}

--- Kinds of notes, in order.
M.TYPES = {
  { key = "topic", label = "Topic notes" },
  { key = "project", label = "Project pages" },
  { key = "meeting", label = "Meetings" },
  { key = "daily", label = "Daily notes" },
  { key = "other", label = "Other notes" },
}

---@param s logpose.ListState
---@return logpose.ListEntry[]
function M.collect(s)
  local items = require("logpose.index").build(s.root)
  local info = common.note_info(s.root, items)
  local filter = s.filter:lower()
  local want = {
    daily = filter:find("type:daily", 1, true) ~= nil,
    meeting = filter:find("type:meeting", 1, true) ~= nil,
  }
  local out = {}
  for _, it in ipairs(items) do
    local ft = it.file_type
    local archived = ft == "project" and ((it.fields or {}).archived == "true" or (it.fields or {}).archived == "yes")
    if it.kind == "note" and not archived and (want[ft] or (ft ~= "daily" and ft ~= "meeting")) then
      local created = type((it.fields or {}).created) == "string" and it.fields.created:match("^%d%d%d%d%-%d%d%-%d%d")
      local when = it.date or created or (it.mtime and os.date("%Y-%m-%d", it.mtime)) or ""
      table.insert(out, {
        key = it.file,
        file = it.file,
        item = it,
        when = when,
        info = info[it.file] or { open = {}, checked = 0, tasks = {} },
      })
    end
  end
  return out
end

---@param e logpose.ListEntry
---@return string
local function kind_of(e)
  local ft = e.item.file_type
  return (ft == "meeting" or ft == "project" or ft == "daily") and ft or "topic"
end

M.groupings = {
  {
    key = "type",
    label = "type",
    of = function(e)
      local ft = e.item.file_type
      for i, t in ipairs(M.TYPES) do
        if t.key == ft or (t.key == "other" and i == #M.TYPES) then
          return { { key = t.key, label = t.label, order = i } }
        end
      end
      return {}
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
      if e.item.file_type == "project" then
        error("logpose: a project page belongs to its project (R on the projects screen renames it)", 0)
      end
      local project = to ~= "" and require("logpose.project").normalize(to) or ""
      return require("logpose.edit.save").note(s.root, e.file, kind_of(e), { project = project or "" })
    end,
  },
  {
    key = "tag",
    label = "tag",
    none = "No tags",
    ask = "New tag: ",
    of = function(e)
      return vim.tbl_map(function(t)
        return { key = t, label = "#" .. t }
      end, e.item.fm_tags or {})
    end,
    targets = function(s)
      local out = {}
      for _, c in ipairs(require("logpose.index").tag_counts(require("logpose.index").build(s.root))) do
        table.insert(out, { key = c.tag, label = "#" .. c.tag })
      end
      table.insert(out, { key = "", label = "No tags" })
      return out
    end,
    move = function(s, e, from, to)
      to = to:gsub("^#", ""):lower()
      return common.swap_in_list(s.root, e.file, kind_of(e), "tags", e.item.fm_tags or {}, from, to)
    end,
  },
  {
    key = "month",
    label = "month",
    descending = true,
    none = "No date",
    of = function(e)
      return common.month_group(e.when)
    end,
  },
}

M.sorts = {
  { label = "newest first", cmp = common.newest },
  { label = "oldest first", cmp = common.oldest },
  { label = "by title", cmp = common.by_title },
}

function M.layout(ctx)
  ctx.day_w = common.day_width(ctx.entries)
  ctx.title_w = common.title_width(ctx.entries, ctx.width, 2 + ctx.day_w + 2 + 30, 48)
end

---@param e logpose.ListEntry
---@param ctx table
---@return table[]
function M.row(e, ctx)
  local date = require("logpose.util.date")
  local it = e.item
  local title = it.file_type == "daily" and date.weekday_name(it.date or e.when) or (it.title or "")
  local chunks = {
    { lists.fit(common.day(e.when), ctx.day_w), "LogposeListDate" },
    { "  " },
    { lists.fit(title, ctx.title_w) },
  }
  local meta = {}
  if #e.info.open > 0 then
    table.insert(meta, { ("☐ %d to-do%s"):format(#e.info.open, #e.info.open == 1 and "" or "s"), "LogposeListTodos" })
  end
  if #e.info.tasks > 0 then
    table.insert(
      meta,
      { ("→ %d task%s"):format(#e.info.tasks, #e.info.tasks == 1 and "" or "s"), "LogposeListTasks" }
    )
  end
  if ctx.all_projects and it.project then
    table.insert(meta, { "◆ " .. it.project, ctx.hl(it.project) })
  end
  if #(it.fm_tags or {}) > 0 then
    table.insert(meta, {
      table.concat(
        vim.tbl_map(function(t)
          return "#" .. t
        end, it.fm_tags),
        " "
      ),
      "LogposeListMeta",
    })
  end
  return common.with_meta(chunks, meta)
end

function M.details(e)
  local out = {}
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

--- A new topic note, in this group's project or with its tag.
function M.add(s, group)
  local defaults = { project = s.project }
  local by = s.view.groupings[s.group].key
  if by == "project" then
    defaults.project = group ~= "" and group or nil
  elseif by == "tag" and group and group ~= "" then
    defaults.tags = { group }
  end
  require("logpose.edit").open_new_note(s.root, "topic", defaults)
end

function M.keys(_, map)
  map("d", function()
    vim.cmd("Logpose daily")
  end, "Daily note")
  map("b", function()
    vim.cmd("Logpose board")
  end, "Board")
end

M.command = lists.command_for(M)

---@param arglead string
function M.complete(arglead, _)
  return require("logpose.search").complete(arglead, { "notes" })
end

return M

--- `:Logpose find [scope] [filters…]` and `:Logpose grep [text]`.
local config = require("logpose.config")
local index = require("logpose.index")
local picker = require("logpose.picker")
local query = require("logpose.query")
local ui = require("logpose.util.ui")

local M = {}

M.SCOPES =
  { "notes", "daily", "meetings", "topics", "archives", "tasks", "decisions", "blockers", "tags", "projects", "people" }

local SCOPE_FILTER = {
  notes = function(it)
    return it.kind == "note"
  end,
  daily = function(it)
    return it.kind == "note" and it.note_type == "daily"
  end,
  meetings = function(it)
    return it.kind == "note" and it.note_type == "meeting"
  end,
  topics = function(it)
    return it.kind == "note" and (it.note_type == "topic" or it.note_type == "project")
  end,
  archives = function(it)
    return it.kind == "note" and it.note_type == "archive"
  end,
  tasks = function(it)
    return it.kind == "task"
  end,
  decisions = function(it)
    return it.kind ~= "note" and it.section ~= nil and it.section:find("decision", 1, true) ~= nil
  end,
  blockers = function(it)
    return it.kind ~= "note" and it.section ~= nil and it.section:find("blocker", 1, true) ~= nil
  end,
}

--- One-line label for an item.
---@param it logpose.Item
---@return string
function M.display(it)
  local project = it.project and ("  @" .. it.project) or ""
  if it.kind == "note" then
    local label = it.type and (it.note_type .. "/" .. it.type) or it.note_type
    return ("%s  %s  %s%s"):format(it.date or "----------", label, it.text, project)
  end
  local where = it.title or vim.fn.fnamemodify(it.file, ":t:r")
  if it.section_title then
    where = where .. " › " .. it.section_title
  end
  if it.kind == "task" then
    return ("[%s] %s  · %s%s"):format(it.checked and "x" or " ", it.text, where, project)
  end
  return ("%s  · %s%s"):format(it.text, where, project)
end

--- Newest first; for tasks, open before done.
---@param items logpose.Item[]
---@return logpose.Item[]
function M.sort(items)
  table.sort(items, function(a, b)
    if a.kind == "task" and b.kind == "task" and a.checked ~= b.checked then
      return not a.checked
    end
    local da, db = a.date or "", b.date or ""
    if da ~= db then
      return da > db
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.lnum < b.lnum
  end)
  return items
end

---@param items logpose.Item[]
---@return logpose.PickItem[]
local function to_pick(items)
  return vim.tbl_map(function(it)
    return { display = M.display(it), file = it.file, lnum = it.lnum, item = it }
  end, items)
end

--- Items matching a typed query; invalid or half-typed filters are ignored while typing.
---@param items logpose.Item[] sorted
---@param text string
---@return logpose.Item[]
function M.live_filter(items, text)
  local q = query.parse(query.split(text), nil, true)
  return query.filter(items, q)
end

--- Show `items` in the picker. With `search.live`, the prompt starts as `initial` and re-filters
--- them with the query language as you type; otherwise `initial` is applied once.
---@param items logpose.Item[]
---@param prompt string
---@param root string
---@param initial? string[] filters
local function show(items, prompt, root, initial)
  items = M.sort(items)
  local text = table.concat(initial or {}, " ")
  if config.get().search.live and picker.supports_live() then
    picker.live({
      prompt = prompt,
      cwd = root,
      query = text == "" and "" or (text .. " "),
      items = function(typed)
        return to_pick(M.live_filter(items, typed))
      end,
    })
    return
  end
  if text ~= "" then
    items = query.filter(items, query.parse(initial))
    prompt = prompt .. " " .. text
  end
  if #items == 0 then
    vim.notify("logpose: no matches", vim.log.levels.INFO)
    return
  end
  picker.pick(to_pick(items), { prompt = prompt, cwd = root })
end

--- Preview text for a list entry: the first items it leads to.
---@param items logpose.Item[]
---@return string
local function list_preview(items)
  items = M.sort(vim.list_extend({}, items))
  local lines = {}
  for i = 1, math.min(#items, 50) do
    lines[i] = "- " .. M.display(items[i])
  end
  if #items > 50 then
    table.insert(lines, ("… and %d more"):format(#items - 50))
  end
  return table.concat(lines, "\n")
end

--- Items carrying `tag`: tasks and lines with it, notes tagging it in frontmatter.
---@param items logpose.Item[]
---@param tag string
---@return logpose.Item[]
function M.with_tag(items, tag)
  return vim.tbl_filter(function(it)
    local tags = it.kind == "note" and (it.fm_tags or {}) or it.tags
    return vim.tbl_contains(tags, tag)
  end, items)
end

--- Notes and tasks of `project` (by frontmatter or #project tag).
---@param items logpose.Item[]
---@param name string
---@return logpose.Item[]
function M.of_project(items, name)
  return vim.tbl_filter(function(it)
    if it.kind == "line" then
      return false
    end
    -- A note belongs by frontmatter (project or tag); a task also by an inline #tag.
    local tags = it.kind == "note" and (it.fm_tags or {}) or it.tags
    return it.project == name or vim.tbl_contains(tags, name)
  end, items)
end

--- Known projects: from the index plus the configured/meeting-folder ones.
---@param root string
---@param items logpose.Item[]
---@return string[]
function M.projects(root, items)
  local seen, out = {}, {}
  for _, list in ipairs({ index.projects(items), require("logpose.project").known(root) }) do
    for _, name in ipairs(list) do
      if not seen[name] then
        seen[name] = true
        table.insert(out, name)
      end
    end
  end
  table.sort(out)
  return out
end

---@param root string
---@param scope string
---@param args string[] filters
function M.find(root, scope, args)
  local all = index.build(root)
  local items = query.filter(all, query.parse(args))
  local suffix = #args > 0 and (" " .. table.concat(args, " ")) or ""

  if scope == "tags" then
    local counts = index.tag_counts(items)
    if #counts == 0 then
      vim.notify("logpose: no tags found", vim.log.levels.INFO)
      return
    end
    local entries = vim.tbl_map(function(c)
      return {
        display = ("#%s (%d)"):format(c.tag, c.count),
        tag = c.tag,
        preview = list_preview(M.with_tag(items, c.tag)),
      }
    end, counts)
    picker.pick(entries, {
      prompt = "Tags" .. suffix,
      cwd = root,
      on_choice = function(choice)
        show(M.with_tag(items, choice.tag), "#" .. choice.tag, root)
      end,
    })
    return
  end

  if scope == "people" then
    local people = index.people(items)
    if #people == 0 then
      vim.notify("logpose: no people found", vim.log.levels.INFO)
      return
    end
    local entries = vim.tbl_map(function(p)
      return {
        display = ("%s (%d)"):format(p.name, p.count),
        person = p.slug,
        name = p.name,
        preview = list_preview(vim.tbl_filter(function(it)
          return vim.tbl_contains(it.people or {}, p.slug)
        end, items)),
      }
    end, people)
    picker.pick(entries, {
      prompt = "People" .. suffix,
      cwd = root,
      on_choice = function(choice)
        local involving = vim.tbl_filter(function(it)
          return vim.tbl_contains(it.people or {}, choice.person)
        end, items)
        show(involving, choice.name, root)
      end,
    })
    return
  end

  if scope == "projects" then
    local names = M.projects(root, items)
    if #names == 0 then
      vim.notify("logpose: no projects found", vim.log.levels.INFO)
      return
    end
    local entries = vim.tbl_map(function(name)
      local of = M.of_project(items, name)
      return { display = ("%s (%d)"):format(name, #of), project = name, preview = list_preview(of) }
    end, names)
    picker.pick(entries, {
      prompt = "Projects" .. suffix,
      cwd = root,
      on_choice = function(choice)
        show(M.of_project(items, choice.project), "Project " .. choice.project, root)
      end,
    })
    return
  end

  local keep = SCOPE_FILTER[scope]
  if not keep then
    error(("logpose: unknown scope %q. Valid: %s"):format(scope, table.concat(M.SCOPES, ", ")), 0)
  end
  local label = scope:sub(1, 1):upper() .. scope:sub(2)
  -- The filters go into the prompt (live) or are applied once, so start from the whole scope.
  show(vim.tbl_filter(keep, all), label, root, args)
end

---@param opts logpose.CommandOpts
function M.find_command(opts)
  local args = vim.list_extend({}, opts.args)
  local scope = "notes"
  if args[1] and vim.tbl_contains(M.SCOPES, args[1]) then
    scope = table.remove(args, 1)
  end
  query.parse(args) -- validate before any prompt
  config.with_root(ui.safely(function(root)
    M.find(root, scope, args)
  end))
end

---@param opts logpose.CommandOpts
function M.grep_command(opts)
  local text = table.concat(opts.args, " ")
  config.with_root(ui.safely(function(root)
    picker.grep({ cwd = root, text = text ~= "" and text or nil })
  end))
end

--- Completion: scopes, then filters with known projects, tags and meeting types.
---@param args string[]
---@return string[]
function M.complete(_, args)
  if #args == 0 then
    return M.SCOPES
  end
  local out = { "open", "done", "since:", "until:", "sprint:current", "sprint:-1", "week:current", "week:-1" }
  for _, name in ipairs(config.get().retrieval.sections) do
    table.insert(out, "section:" .. name:gsub("%s", "-"))
  end
  local root = config.resolve_root()
  if root then
    local items = index.build(root)
    for _, name in ipairs(M.projects(root, items)) do
      table.insert(out, "project:" .. name)
    end
    for _, c in ipairs(index.tag_counts(items)) do
      table.insert(out, "#" .. c.tag)
    end
    for _, p in ipairs(index.people(items)) do
      table.insert(out, "person:" .. p.slug)
    end
  end
  for _, t in ipairs(require("logpose.notes.meeting").types()) do
    table.insert(out, "type:" .. t.key)
  end
  return out
end

return M

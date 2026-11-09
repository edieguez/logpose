--- The project page as a hub: a section of `projects/<project>.md` that logpose keeps up to date,
--- between `<!-- logpose:hub -->` and `<!-- /logpose:hub -->` (Obsidian and GitHub hide the
--- markers), listing the project's docs by type, its topic notes (those with `project:` set and
--- those linking to the page) and its latest meetings. It follows on its own a moment after
--- anything in the journal changes; `:Logpose hub [project]` does it now (`!`: every project).
--- The page is written only when the section's text changes, and never while it has unsaved
--- changes.
local config = require("logpose.config")
local fs = require("logpose.util.fs")

local M = {}

M.START = "<!-- logpose:hub -->"
M.END = "<!-- /logpose:hub -->"
M.HEADING = "## In this project"
M.MEETINGS = 3 -- the latest ones listed

---@param it logpose.Item
---@param root string
local function archived_doc(it, root)
  return require("logpose.index").in_project_archive(it.file, root)
end

--- The section's lines (between the markers) for a project: nil when there's nothing to list.
---@param root string
---@param project string
---@param page string the page's path (links are written from it)
---@param items logpose.Item[]
---@return string[]?
function M.lines(root, project, page, items)
  local link = require("logpose.link")
  local date = require("logpose.util.date")
  local docs, notes, meetings = {}, {}, {}
  local seen = {}
  for _, it in ipairs(items) do
    if it.kind == "note" and it.project == project then
      if it.file_type == "doc" and not archived_doc(it, root) then
        local t = it.type or "doc"
        docs[t] = docs[t] or {}
        table.insert(docs[t], it)
      elseif it.file_type == "topic" then
        seen[it.file] = true
        table.insert(notes, it)
      elseif it.file_type == "meeting" then
        table.insert(meetings, it)
      end
    end
  end
  -- topic notes that link to the page belong here too
  local links = require("logpose.links")
  local by_name
  local want = fs.normalize(page)
  for _, it in ipairs(items) do
    if it.kind == "note" and it.file_type == "topic" and not seen[it.file] and #(it.links or {}) > 0 then
      by_name = by_name or links.names(items)
      for _, l in ipairs(it.links) do
        local target = links.resolve(root, it.file, l, by_name)
        if target and fs.normalize(target) == want then
          seen[it.file] = true
          table.insert(notes, it)
          break
        end
      end
    end
  end
  local function by_title(a, b)
    return (a.title or ""):lower() < (b.title or ""):lower()
  end
  local function item(it, extra)
    local l = "  - " .. link.make(page, it.file, it.title or vim.fn.fnamemodify(it.file, ":t:r"), root)
    return extra and (l .. " · " .. extra) or l
  end
  local out = {}
  local doc = require("logpose.notes.doc")
  local listed = {}
  local function add_docs(key, label)
    local list = docs[key]
    if not list or #list == 0 then
      return
    end
    listed[key] = true
    table.sort(list, by_title)
    table.insert(out, "- " .. label)
    for _, it in ipairs(list) do
      local status = type((it.fields or {}).status) == "string" and it.fields.status ~= "" and it.fields.status
      table.insert(out, item(it, status or nil))
    end
  end
  for _, t in ipairs(doc.types()) do
    add_docs(t.key, t.spec.plural or ((t.spec.label or t.key) .. "s"))
  end
  local others = vim.tbl_filter(function(k)
    return not listed[k]
  end, vim.tbl_keys(docs))
  table.sort(others)
  for _, k in ipairs(others) do
    add_docs(k, k)
  end
  if #notes > 0 then
    table.sort(notes, by_title)
    table.insert(out, "- Notes")
    for _, it in ipairs(notes) do
      table.insert(out, item(it))
    end
  end
  if #meetings > 0 then
    table.sort(meetings, function(a, b)
      if (a.date or "") ~= (b.date or "") then
        return (a.date or "") > (b.date or "")
      end
      return by_title(a, b)
    end)
    table.insert(out, ("- Meetings (%d)"):format(#meetings))
    for k = 1, math.min(M.MEETINGS, #meetings) do
      local it = meetings[k]
      table.insert(out, item(it, it.date and date.short(it.date) or nil))
    end
  end
  return #out > 0 and out or nil
end

--- The page with its hub section set to `section` (added at the end the first time).
---@param lines string[]
---@param section string[]
---@return string[]
function M.with_section(lines, section)
  local s, e
  for i, l in ipairs(lines) do
    if vim.trim(l) == M.START then
      s = i
    elseif s and vim.trim(l) == M.END then
      e = i
      break
    end
  end
  local block = vim.list_extend({ M.START }, section)
  table.insert(block, M.END)
  local out = {}
  if s and e then
    vim.list_extend(out, vim.list_slice(lines, 1, s - 1))
    vim.list_extend(out, block)
    vim.list_extend(out, vim.list_slice(lines, e + 1))
    return out
  end
  out = vim.deepcopy(lines)
  while #out > 0 and vim.trim(out[#out]) == "" do
    table.remove(out)
  end
  vim.list_extend(out, { "", M.HEADING, "" })
  vim.list_extend(out, block)
  return out
end

--- Bring one project's hub up to date. Returns "updated", "same", "busy" (unsaved changes in
--- the page), "nothing" (nothing to list yet, and no section), "archived" or "no page".
---@param root string
---@param project string
---@param items? logpose.Item[]
---@return string
function M.update(root, project, items)
  local info = require("logpose.project").pages(root)[project]
  if not info then
    return "no page"
  end
  if info.archived then
    return "archived"
  end
  local page = info.path
  items = items or require("logpose.index").build(root)
  local section = M.lines(root, project, page, items) or { "- Nothing yet" }
  local buf = fs.find_buf(page)
  if buf and vim.bo[buf].modified then
    return "busy"
  end
  local current = fs.current_lines(page) or {}
  local has = false
  for _, l in ipairs(current) do
    if vim.trim(l) == M.START then
      has = true
      break
    end
  end
  if not has and section[1] == "- Nothing yet" then
    return "nothing"
  end
  local new = M.with_section(current, section)
  if vim.deep_equal(new, current) then
    return "same"
  end
  -- not your edit: `modified:` stays as it was
  local ok, err = fs.write_file(page, table.concat(new, "\n") .. "\n", { raw = true })
  if not ok then
    error(err, 0)
  end
  return "updated"
end

--- Every project with a page. Returns the projects whose page changed.
---@param root string
---@return string[]
function M.update_all(root)
  local items = require("logpose.index").build(root)
  local changed = {}
  for name in pairs(require("logpose.project").pages(root)) do
    local ok, res = pcall(M.update, root, name, items)
    if ok and res == "updated" then
      table.insert(changed, name)
    end
  end
  table.sort(changed)
  return changed
end

local timer
local running = false

--- Update the hubs a moment from now (called whenever the journal changes; calls in a burst
--- make one update).
function M.schedule()
  if running or not config.get().projects.hub then
    return
  end
  timer = timer or (vim.uv or vim.loop).new_timer()
  timer:stop()
  timer:start(
    M.DELAY,
    0,
    vim.schedule_wrap(function()
      local root = config.get().projects.hub and config.resolve_root()
      if not root then
        return
      end
      running = true -- our own writes don't schedule another round
      pcall(M.update_all, root)
      running = false
    end)
  )
end

M.DELAY = 300

---@param opts logpose.CommandOpts
function M.command(opts)
  local ui = require("logpose.util.ui")
  config.with_root(ui.safely(function(root)
    if opts.bang then
      running = true
      local ok, changed = pcall(M.update_all, root)
      running = false
      if not ok then
        error(changed, 0)
      end
      ui.notify(
        #changed > 0 and ("logpose: updated the hub of %s"):format(table.concat(changed, ", "))
          or "logpose: every hub is up to date",
        vim.log.levels.INFO
      )
      return
    end
    local project = opts.args[1]
    if not project then
      local file = vim.api.nvim_buf_get_name(0)
      local index = require("logpose.index")
      if index.file_type(file, root) == "project" then
        project = vim.fn.fnamemodify(file, ":t:r")
      end
      project = project or index.doc_project(file, root) or require("logpose.project").resolve(root)
    end
    if not project then
      error("logpose: which project? :Logpose hub <project> (or ! for all)", 0)
    end
    running = true
    local ok, res = pcall(M.update, root, require("logpose.project").normalize(project) or project)
    running = false
    if not ok then
      error(res, 0)
    end
    local msg = ({
      updated = "updated the hub of %s",
      same = "the hub of %s is up to date",
      busy = "%s's page has unsaved changes: save it first",
      ["nothing"] = "nothing to list for %s yet",
      ["no page"] = "%s has no project page (:Logpose project-page makes one)",
      archived = "%s is archived: its page keeps the list it had",
    })[res]
    ui.notify("logpose: " .. msg:format(project), vim.log.levels.INFO)
  end))
end

function M.complete(_, args)
  if #args > 0 then
    return {}
  end
  local root = config.resolve_root()
  return root and vim.tbl_keys(require("logpose.project").pages(root)) or {}
end

return M

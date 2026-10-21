--- A task's write-up promoted to a topic note: `:Logpose promote` in a task file (or a selection
--- of it), `N` on the board. The new-note form opens filled in from the task, with a `content`
--- field: `copy` keeps the write-up in the task too, `move` leaves only the link there. Either way
--- the two link to each other: the note starts with `From: [[task]]`, the task gets the note
--- under `## Notes`.
local fm = require("logpose.frontmatter")
local fs = require("logpose.util.fs")

local M = {}

--- Sections of a task that stay out of the write-up: its history, and the links logpose adds.
local KEEP_OUT = { log = true, notes = true }

--- The rows (1-based) of the write-up in a task's lines, optionally only within `line1..line2`:
--- the body, without `## Log`, `## Notes` and the task's own `From:` line.
---@param lines string[]
---@param line1? integer
---@param line2? integer
---@return integer[]
function M.rows(lines, line1, line2)
  local close = fm.close(lines) or 0
  local first, last = close + 1, #lines
  if line1 and line2 then
    first, last = math.max(first, line1), math.min(last, line2)
  end
  -- which section a row is in, from the top (a selection may start inside one)
  local out = {}
  local section
  for i = close + 1, last do
    local h = lines[i]:match("^##%s+(.-)%s*$")
    if h then
      section = h:lower()
    end
    if i >= first and not KEEP_OUT[section] and not lines[i]:match("^From:%s") then
      table.insert(out, i)
    end
  end
  -- no blank rows at either end
  while out[1] and vim.trim(lines[out[1]]) == "" do
    table.remove(out, 1)
  end
  while out[#out] and vim.trim(lines[out[#out]]) == "" do
    table.remove(out)
  end
  return out
end

--- The write-up's text.
---@param lines string[]
---@param rows integer[]
---@return string[]
function M.text(lines, rows)
  return vim.tbl_map(function(i)
    return lines[i]
  end, rows)
end

--- Lines with `item` added under `## Notes` (created before `## Log`, or at the end).
---@param lines string[]
---@param item string
---@return string[]
function M.add_to_notes(lines, item)
  local out = vim.list_extend({}, lines)
  local notes, log
  for i, l in ipairs(out) do
    local h = l:match("^##%s+(.-)%s*$")
    if h and h:lower() == "notes" then
      notes = i
    elseif h and h:lower() == "log" then
      log = log or i
    end
  end
  if notes then
    local at = notes
    for i = notes + 1, #out do
      if out[i]:match("^#") then
        break
      end
      if vim.trim(out[i]) ~= "" then
        at = i
      end
    end
    table.insert(out, at + 1, item)
    return out
  end
  local block = { "## Notes", "", item, "" }
  local at = log or (#out + 1)
  for j = #block, 1, -1 do
    table.insert(out, at, block[j])
  end
  return out
end

--- What the task offers: its title, project, tags and the write-up's size.
---@param root string
---@param path string
---@param line1? integer
---@param line2? integer
---@return { path: string, title: string, project?: string, tags: string[], lines: integer, selection: boolean }
function M.info(root, path, line1, line2)
  local lines = require("logpose.edit.fields").note_lines(path)
  local t = require("logpose.taskfile").parse(path, lines, root)
  local rows = M.rows(lines, line1, line2)
  local n = 0
  for _, i in ipairs(rows) do
    if vim.trim(lines[i]) ~= "" then
      n = n + 1
    end
  end
  return {
    path = path,
    title = t.title or vim.fn.fnamemodify(path, ":t:r"),
    project = t.project,
    tags = t.tags or {},
    lines = line1 and (line2 - line1 + 1) or n, -- a selection: as selected; else its text lines
    selection = line1 ~= nil,
    line1 = line1,
    line2 = line2,
  }
end

--- Open the new-note form for the task at `path` (its write-up, or lines `line1..line2`).
---@param root string
---@param path string
---@param line1? integer
---@param line2? integer
---@param opts? { on_save?: fun(path: string, keys: string[]) }
function M.open(root, path, line1, line2, opts)
  local info = M.info(root, path, line1, line2)
  require("logpose.edit").open_new_note(root, "topic", {
    title = info.title,
    project = info.project,
    tags = info.tags,
    from_task = info,
  }, opts)
end

--- Save: create the note (or add to the one with that title), link the two both ways and, with
--- `move`, take the write-up out of the task. Returns the note's path, where the cursor goes,
--- and what happened in words.
---@param root string
---@param info table  from `M.info`
---@param v table<string, any>  the form's checked values
---@return string path, integer[]? cursor, string message
function M.apply(root, info, v)
  local link = require("logpose.link")
  local topic = require("logpose.notes.topic")
  local title = vim.trim(v.title)
  local note = topic.note_path(root, title)
  if not note then
    error(("logpose: can't make a filename from %q"):format(title), 0)
  end
  local task_lines = require("logpose.edit.fields").note_lines(info.path)
  local rows = M.rows(task_lines, info.line1, info.line2)
  local body = { "From: " .. link.make(note, info.path, info.title, root), "" }
  vim.list_extend(body, M.text(task_lines, rows))
  local project = type(v.project) == "string" and v.project ~= "" and v.project or false
  local tags = type(v.tags) == "table" and v.tags or {}
  local cursor, existed
  if fs.exists(note) then
    existed = true
    local ok, err = fs.update_lines(note, function(lines)
      local out = vim.list_extend({}, lines)
      while out[#out] and vim.trim(out[#out]) == "" do
        table.remove(out)
      end
      table.insert(out, "")
      vim.list_extend(out, body)
      cursor = { #out, 0 }
      return out
    end, { tidy = true })
    if not ok then
      error(err, 0)
    end
  else
    local _
    _, cursor = topic.note(root, title, { project = project, tags = tags, open = false, body = body })
  end
  -- the task: the link to the note, and without the write-up when it moved
  local item = "- " .. link.make(info.path, note, title, root)
  local ok, err = fs.update_lines(info.path, function(lines)
    local out = lines
    if v.content == "move" then
      local drop = {}
      for _, i in ipairs(M.rows(lines, info.line1, info.line2)) do
        drop[i] = true
      end
      out = {}
      for i, l in ipairs(lines) do
        if not drop[i] then
          table.insert(out, l)
        end
      end
    end
    return M.add_to_notes(out, item)
  end, { tidy = true })
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  local rel = link.relpath(root, note)
  local message = existed and ("logpose: added the task's write-up to %s"):format(rel)
    or ("logpose: created %s from the task"):format(rel)
  if v.content == "move" then
    message = message .. " (moved out of the task)"
  end
  return note, cursor, message
end

--- `N` on the board, `:Logpose promote` in a task file.
---@param root string
---@param path string
---@param opts? logpose.CommandOpts
function M.command(root, path, opts)
  local line1, line2
  if opts and opts.range and opts.range > 0 then
    line1, line2 = opts.line1, opts.line2
  end
  M.open(root, path, line1, line2)
end

return M

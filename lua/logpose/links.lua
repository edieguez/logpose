--- Links between notes: resolution, backlinks, outgoing links, and `[[` completion items.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local index = require("logpose.index")

local M = {}

---@param path string
---@return string
local function canonical(path)
  return vim.fs.normalize(path)
end

--- Resolve a raw link found in `from` to an absolute path (nil if no such note).
--- Wiki targets are relative to `link_base`; when that misses, a unique note with the same
--- name anywhere in the journal matches (Obsidian-style short links).
---@param root string
---@param from string
---@param link { target: string, style: string }
---@param by_name table<string, string[]> lowercased filename stem -> paths
---@return string?
function M.resolve(root, from, link, by_name)
  local target = link.target
  local with_ext = target:match("%.md$") and target or (target .. ".md")
  local candidates = {}
  if link.style == "markdown" then
    table.insert(candidates, fs.join(vim.fs.dirname(from), with_ext))
  else
    table.insert(candidates, fs.join(root, config.get().link_base, with_ext))
  end
  for _, c in ipairs(candidates) do
    local abs = vim.fs.normalize(vim.fn.fnamemodify(c, ":p"))
    if fs.exists(abs) then
      return abs
    end
  end
  local stem = vim.fn.fnamemodify(target, ":t"):gsub("%.md$", ""):lower()
  local hits = by_name[stem]
  if hits and #hits == 1 then
    return hits[1]
  end
  return nil
end

---@param items logpose.Item[]
---@return table<string, string[]>
local function names(items)
  local by_name = {}
  for _, it in ipairs(items) do
    if index.is_file(it) then
      local stem = vim.fn.fnamemodify(it.file, ":t:r"):lower()
      by_name[stem] = by_name[stem] or {}
      table.insert(by_name[stem], it.file)
    end
  end
  return by_name
end

---@class logpose.Link
---@field from string   file containing the link
---@field lnum integer
---@field text string   the line
---@field title string  title of the linking note
---@field target? string resolved path (nil when missing)
---@field raw string

--- All links in the journal, resolved.
---@param root string
---@param items? logpose.Item[]
---@return logpose.Link[]
function M.all(root, items)
  items = items or index.build(root)
  local by_name = names(items)
  local out = {}
  for _, it in ipairs(items) do
    if index.is_file(it) then
      for _, l in ipairs(it.links or {}) do
        table.insert(out, {
          from = it.file,
          lnum = l.lnum,
          text = l.text,
          title = it.title,
          raw = l.target,
          target = M.resolve(root, it.file, l, by_name),
        })
      end
    end
  end
  return out
end

--- The notes linked with each task file, both ways: notes (meetings, daily and topic notes,
--- project pages) linking to the task, and notes the task links to (like the `From:` link a
--- promoted checkbox gets). Links between tasks don't count. Only links that could reach a task
--- are resolved, so this stays cheap on a big journal. Newest first.
---@param root string
---@param items? logpose.Item[]
---@return table<string, { file: string, title: string, file_type: string, date?: string, lnum: integer }[]>  by task file
function M.related(root, items)
  items = items or index.build(root)
  -- plain string work here: this runs on every board refresh, over every link in the journal
  local function stem(path)
    -- `^.*/` finds the last slash in one pass (`[^/]+$` retries from every position)
    return (path:match("^.*/(.*)$") or path):gsub("%.md$", ""):lower()
  end
  local notes, tasks, stems = {}, {}, {}
  for _, it in ipairs(items) do
    if index.is_file(it) then
      notes[it.file] = it
      if it.kind == "task" then
        tasks[it.file] = true
        stems[stem(it.file)] = true
      end
    end
  end
  local by_name -- built only when a link might reach a task
  local out, seen = {}, {}
  local function add(task, note, lnum)
    local key = task .. "\0" .. note.file
    if seen[key] then
      return
    end
    seen[key] = true
    out[task] = out[task] or {}
    table.insert(out[task], {
      file = note.file,
      title = note.title or stem(note.file),
      file_type = note.file_type,
      date = note.date,
      lnum = lnum,
    })
  end
  for file, it in pairs(notes) do
    local from_task = tasks[file]
    for _, l in ipairs(it.links or {}) do
      if from_task or stems[stem(l.target)] then
        by_name = by_name or names(items)
        local target = M.resolve(root, file, l, by_name)
        if target and target ~= file then
          if from_task and notes[target] and not tasks[target] then
            add(file, notes[target], 1)
          elseif not from_task and tasks[target] then
            add(target, it, l.lnum)
          end
        end
      end
    end
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b)
      if (a.date or "") ~= (b.date or "") then
        return (a.date or "") > (b.date or "")
      end
      return a.title < b.title
    end)
  end
  return out
end

--- Links pointing at `file`.
---@param root string
---@param file string
---@return logpose.Link[]
function M.backlinks(root, file)
  local target = canonical(file)
  return vim.tbl_filter(function(l)
    return l.target ~= nil and canonical(l.target) == target and canonical(l.from) ~= target
  end, M.all(root))
end

--- Links going out of `file`.
---@param root string
---@param file string
---@return logpose.Link[]
function M.outgoing(root, file)
  local from = canonical(file)
  return vim.tbl_filter(function(l)
    return canonical(l.from) == from
  end, M.all(root))
end

---@return string root, string file
local function current()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    error("logpose: the current buffer is not a file", 0)
  end
  return config.root(), fs.normalize(file)
end

function M.backlinks_command()
  local root, file = current()
  local found = M.backlinks(root, file)
  if #found == 0 then
    require("logpose.util.ui").notify("logpose: no backlinks", vim.log.levels.INFO)
    return
  end
  require("logpose.picker").pick(
    vim.tbl_map(function(l)
      return { display = ("%s: %s"):format(l.title, l.text), file = l.from, lnum = l.lnum }
    end, found),
    { prompt = "Backlinks", cwd = root }
  )
end

function M.links_command()
  local root, file = current()
  local found = M.outgoing(root, file)
  if #found == 0 then
    require("logpose.util.ui").notify("logpose: no links in this note", vim.log.levels.INFO)
    return
  end
  require("logpose.picker").pick(
    vim.tbl_map(function(l)
      if not l.target then
        return { display = l.raw .. "  (missing)", file = l.from, lnum = l.lnum }
      end
      return { display = require("logpose.link").relpath(root, l.target), file = l.target, lnum = 1 }
    end, found),
    { prompt = "Links", cwd = root }
  )
end

--- Completion candidates for a link written into `source`: one per note or task, newest first.
---@param root string
---@param source string
---@return { label: string, detail: string, link: string, file: string }[]
function M.candidates(root, source)
  local link = require("logpose.link")
  local notes = vim.tbl_filter(function(it)
    return index.is_file(it) and canonical(it.file) ~= canonical(source)
  end, index.build(root))
  require("logpose.search").sort(notes)
  return vim.tbl_map(function(it)
    return {
      label = it.title,
      detail = (it.kind == "task" and "task · " or "") .. link.relpath(root, it.file),
      link = link.make(source, it.file, it.title, root),
      file = it.file,
    }
  end, notes)
end

--- LSP-style completion items for the text before the cursor, when it ends in `[[partial`.
--- The text edit replaces `[[partial` with a full link (wiki or markdown per `link_style`).
---@param line string full current line
---@param col integer cursor column (0-based, bytes)
---@param row integer cursor row (0-based)
---@param source string file being edited
---@return table[] items
function M.complete_items(line, col, row, source)
  local before = line:sub(1, col)
  local start = before:find("%[%[[^%]%[]*$")
  if not start then
    return {}
  end
  local root = config.resolve_root()
  if not root then
    return {}
  end
  local items = {}
  for i, c in ipairs(M.candidates(root, source)) do
    table.insert(items, {
      label = c.label,
      detail = c.detail,
      kind = 17, -- File
      filterText = "[[" .. c.label,
      sortText = ("%05d"):format(i),
      textEdit = {
        newText = c.link,
        range = { start = { line = row, character = start - 1 }, ["end"] = { line = row, character = col } },
      },
    })
  end
  return items
end

return M

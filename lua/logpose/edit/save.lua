--- Saving the frontmatter editor's changes the way logpose would: a task's status, project and
--- blocker through `taskfile` (logged, `started`/`done` kept), a meeting moved to another
--- project's folder with the links to it fixed.
local fields = require("logpose.edit.fields")
local fs = require("logpose.util.fs")

local M = {}

--- How many links in the journal point at `path`.
---@param root string
---@param path string
---@return integer
function M.links_to(root, path)
  return #require("logpose.links").backlinks(root, path)
end

--- Move a meeting note to another project's folder: frontmatter, series, links to it (and the
--- `- project:` label of daily-note links).
---@param root string
---@param path string
---@param from? string
---@param to? string
---@return string new_path
function M.move_meeting(root, path, from, to)
  local meeting = require("logpose.notes.meeting")
  local link = require("logpose.link")
  local maintenance = require("logpose.maintenance")
  local dest = fs.join(meeting.dir(root, to), vim.fs.basename(path))
  if dest == path then
    return path
  end
  if fs.exists(dest) then
    error(("logpose: %s already exists"):format(link.relpath(root, dest)), 0)
  end
  local buf = fs.find_buf(path)
  if buf and vim.bo[buf].modified then
    error("logpose: the note has unsaved changes; save it first", 0)
  end
  local rel_old = link.relpath(root, path):gsub("%.md$", "")
  local rel_new = link.relpath(root, dest):gsub("%.md$", "")
  local changes = {}
  -- the note itself: series follows the project
  local lines = fs.read_lines(path) or {}
  for _, e in ipairs(fields.read(lines)) do
    if e.key == "series" and type(e.value) == "string" and e.value ~= "" then
      local rest = (from and e.value:match("^" .. vim.pesc(from) .. "/(.+)$")) or e.value
      local series = to and (to .. "/" .. rest) or rest
      lines = require("logpose.frontmatter").set(lines, { series = series })
    end
  end
  table.insert(changes, { path = path, content = table.concat(lines, "\n") .. "\n", count = 1 })
  for _, file in ipairs(require("logpose.index").files(root)) do
    if file ~= path then
      local flines = fs.read_lines(file) or {}
      local n = 0
      for i, l in ipairs(flines) do
        local nl, moved = maintenance.rewrite_links(l, { { rel_old, rel_new } })
        if moved > 0 then
          -- the daily note's "- acme: [[…]]" label
          if from then
            nl = nl:gsub("^(%s*[-*] )" .. vim.pesc(from) .. ": ", "%1" .. (to and (to .. ": ") or ""))
          elseif to then
            nl = nl:gsub("^(%s*[-*] )(%[%[)", "%1" .. to .. ": %2")
          end
          flines[i], n = nl, n + 1
        end
      end
      if n > 0 then
        table.insert(changes, { path = file, content = table.concat(flines, "\n") .. "\n", count = n })
      end
    end
  end
  table.insert(changes, { path = path, move_to = dest, count = 0 })
  -- the old project's meeting folder, if this was its last note (only removed when empty)
  table.insert(changes, { path = vim.fs.dirname(path), rmdir = true, count = 0 })
  maintenance.apply(changes)
  if buf then
    -- show the moved note where the old one was
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        vim.cmd.edit(vim.fn.fnameescape(dest))
      end)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  return dest
end

--- Write `changed` to one note. Returns its path (a meeting may have moved) and the keys.
---@param root string
---@param path string
---@param kind string
---@param changed table<string, string|string[]|false>
---@param opts? { batch?: boolean }  batch: leave the index/project notifications to the caller
---@return string path, string[] keys
function M.note(root, path, kind, changed, opts)
  local taskfile = require("logpose.taskfile")
  changed = vim.deepcopy(changed)
  local keys = vim.tbl_keys(changed)
  table.sort(keys)
  if #keys == 0 then
    return path, keys
  end
  local special = {}
  if kind == "task" then
    for _, key in ipairs({ "status", "project", "blocked" }) do
      if changed[key] ~= nil then
        special[key] = changed[key]
        changed[key] = nil
      end
    end
  end
  local meeting_move
  if kind == "meeting" and changed.project ~= nil then
    local old = require("logpose.index").frontmatter(fields.note_lines(path)).project
    meeting_move = { from = (old ~= "" and old) or nil, to = changed.project or nil }
    if meeting_move.to == "" then
      meeting_move.to = nil
    end
  end
  if next(changed) then
    local ok, err = fs.update_lines(path, function(lines)
      return require("logpose.frontmatter").set(lines, changed)
    end, { tidy = true })
    if not ok then
      error(err, 0)
    end
  end
  if special.status ~= nil and special.status ~= "" then
    taskfile.set_status(path, special.status)
  end
  if special.project ~= nil then
    taskfile.set_project(path, special.project ~= "" and special.project or nil)
  end
  if special.blocked ~= nil then
    taskfile.set_blocked(path, (special.blocked ~= "" and special.blocked) or nil)
  end
  if meeting_move then
    path = M.move_meeting(root, path, meeting_move.from, meeting_move.to)
  end
  if not (opts and opts.batch) then
    M.notify_changed(kind, keys)
  end
  return path, keys
end

--- Tell the index (and, when projects may have changed, everything that shows them).
---@param kind string
---@param keys string[]
function M.notify_changed(kind, keys)
  require("logpose.index").clear_cache()
  if
    vim.tbl_contains(keys, "project")
    or vim.tbl_contains(keys, "paths")
    or (kind == "project" and (vim.tbl_contains(keys, "title") or vim.tbl_contains(keys, "color")))
  then
    require("logpose.project").changed()
  end
end

--- Apply a bulk edit to each task: a field left as it was isn't touched, `tags` may add or
--- remove tags (each task keeps its others), and a task already holding the value is skipped.
---@param model logpose.EditModel
---@param changed table<string, any>
---@return integer updated, string[] keys
function M.bulk(model, changed)
  local updated, all_keys, seen = 0, {}, {}
  for _, path in ipairs(model.bulk.paths) do
    local old = model.bulk.olds[path]
    local mine = {}
    for key, v in pairs(changed) do
      if key == "tags" and type(v) == "table" and (v.add or v.remove) then
        local tags = vim.deepcopy(type(old.tags) == "table" and old.tags or {})
        local drop = {}
        for _, t in ipairs(v.remove) do
          drop[t:lower()] = true
        end
        tags = vim.tbl_filter(function(t)
          return not drop[t:lower()]
        end, tags)
        for _, t in ipairs(v.add) do
          local has = false
          for _, x in ipairs(tags) do
            has = has or x:lower() == t:lower()
          end
          if not has then
            table.insert(tags, t)
          end
        end
        v = tags
      end
      if not fields.same(old[key], v) then
        mine[key] = v
      end
    end
    local _, keys = M.note(model.root, path, "task", mine, { batch = true })
    if #keys > 0 then
      updated = updated + 1
    end
    for _, k in ipairs(keys) do
      if not seen[k] then
        seen[k] = true
        table.insert(all_keys, k)
      end
    end
  end
  table.sort(all_keys)
  M.notify_changed("task", all_keys)
  return updated, all_keys
end

return M

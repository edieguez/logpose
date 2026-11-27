--- Previous and next links between notes that follow each other: daily notes, by date, and the
--- meetings of a series. They're links in the frontmatter (`previous:`, `next:`): a new note gets
--- both, and its neighbours are pointed at it. `:Logpose relink[!]` adds or fixes them all.
local fs = require("logpose.util.fs")

local M = {}

--- Where the keys go in the frontmatter: after a meeting's `series`, before the timestamps.
M.ORDER = { "series", "previous", "next", "created", "modified" }

---@class logpose.ChainLink
---@field file string
---@field label string  how a link to it reads

--- How a link to a daily note reads: "Tue 2026-10-13".
---@param iso string
---@return string
function M.daily_label(iso)
  return require("logpose.util.date").weekday_name(iso):sub(1, 3) .. " " .. iso
end

--- How a link to a meeting reads: "Retro 2026-10-08".
---@param title string
---@param iso? string
---@return string
function M.meeting_label(title, iso)
  return iso and (title .. " " .. iso) or title
end

--- A meeting from the index, as a neighbour.
---@param it? logpose.Item
---@return logpose.ChainLink?
function M.meeting_link(it)
  return it and { file = it.file, label = M.meeting_label(it.title, it.date) } or nil
end

--- The value of `from`'s link to `to`: the link, or false when there's no neighbour (no key).
---@param root string
---@param from string
---@param to? logpose.ChainLink
---@return string|false
function M.value(root, from, to)
  if not to then
    return false
  end
  return require("logpose.link").make(from, to.file, to.label, root)
end

--- `lines` with `previous`/`next` set (false removes one).
---@param lines string[]
---@param changes { previous?: string|false, next?: string|false }
---@return string[]
function M.apply(lines, changes)
  return require("logpose.frontmatter").set(lines, changes, { order = M.ORDER })
end

--- Point a note's `previous`/`next` elsewhere. It's bookkeeping, not an edit: `modified:` stays
--- as it was. An unsaved note is changed in its buffer.
---@param path string
---@param changes { previous?: string|false, next?: string|false }
function M.update(path, changes)
  local ok, err = fs.update_lines(path, function(lines)
    local new = M.apply(lines, changes)
    return not vim.deep_equal(new, lines) and new or nil
  end, { raw = true })
  if not ok then
    error(err, 0)
  end
end

--- A note joined the chain between `prev` and `nxt`: they link to it.
---@param root string
---@param note logpose.ChainLink
---@param prev? logpose.ChainLink
---@param nxt? logpose.ChainLink
function M.link_neighbours(root, note, prev, nxt)
  local failed = {}
  for _, n in ipairs({ { prev, "next" }, { nxt, "previous" } }) do
    local other, key = n[1], n[2]
    if other then
      local ok, err = pcall(M.update, other.file, { [key] = M.value(root, other.file, note) })
      if not ok then
        table.insert(failed, tostring(err))
      end
    end
  end
  if #failed > 0 then
    require("logpose.util.ui").notify(
      "logpose: couldn't link the notes around it: " .. table.concat(failed, "; "),
      vim.log.levels.WARN
    )
  end
end

--- The daily notes before and after `iso` (a note for `iso` itself doesn't count).
---@param root string
---@param iso string
---@return logpose.ChainLink? prev, logpose.ChainLink? next
function M.daily_neighbours(root, iso)
  local daily = require("logpose.notes.daily")
  local prev, nxt
  for _, d in ipairs(daily.dates(root)) do
    if d < iso then
      prev = d
    elseif d > iso and not nxt then
      nxt = d
    end
  end
  local function link(d)
    return d and { file = daily.path(d, root), label = M.daily_label(d) } or nil
  end
  return link(prev), link(nxt)
end

--- The `Previous: [[…]]` line a meeting note's body started with before 1.41.0, when the link
--- wasn't in the frontmatter yet: its row, if the note has one.
---@param lines string[]
---@return integer?
function M.old_previous_row(lines)
  local i = (require("logpose.frontmatter").close(lines) or 0) + 1
  while lines[i] and (vim.trim(lines[i]) == "" or lines[i]:match("^#%s")) do
    i = i + 1
  end
  local rest = lines[i] and lines[i]:match("^Previous:%s+(.-)%s*$")
  if not rest then
    return nil
  end
  local found = require("logpose.index").links_in(rest)
  if #found == 1 and found[1].s == 1 and found[1].e == #rest + 1 then
    return i
  end
  return nil
end

--- `lines` without row `row`, nor the blank line that would leave behind.
---@param lines string[]
---@param row integer
---@return string[]
local function drop_row(lines, row)
  local out = vim.list_extend({}, lines)
  table.remove(out, row)
  local close = require("logpose.frontmatter").close(out) or 0
  if out[row] and vim.trim(out[row]) == "" and (row - 1 == close or vim.trim(out[row - 1] or "") == "") then
    table.remove(out, row)
  end
  if row > #out then
    while #out > close and vim.trim(out[#out]) == "" do
      table.remove(out)
    end
  end
  return out
end

--- What `relink` changes in one note: its links, and an old `Previous:` line (`migrate`).
---@param path string
---@param want { previous: string|false, next: string|false }
---@param migrate boolean
---@param changes logpose.Change[]
local function plan_note(path, want, migrate, changes)
  local lines = fs.read_lines(path)
  if not lines then
    return
  end
  if lines[#lines] == "" then
    table.remove(lines)
  end
  local fm = require("logpose.index").frontmatter(lines)
  local delta, count = {}, 0
  for _, key in ipairs({ "previous", "next" }) do
    local have = type(fm[key]) == "string" and fm[key] ~= "" and fm[key] or false
    if have ~= want[key] then
      delta[key] = want[key]
      count = count + 1
    end
  end
  local new = count > 0 and M.apply(lines, delta) or lines
  local row = migrate and M.old_previous_row(new)
  if row then
    new = drop_row(new, row)
    count = count + 1
  end
  if count > 0 then
    table.insert(changes, { path = path, content = table.concat(new, "\n") .. "\n", count = count, raw = true })
  end
end

--- Every daily note and meeting of a series, with the links it should have, against the ones it
--- has: what `relink` would change. Nothing is written. `opts.series`: only those series' meetings
--- (no daily notes).
---@param root string
---@param opts? { series?: string[] }
---@return logpose.Change[]
function M.plan(root, opts)
  local cfg = require("logpose.config").get()
  local only
  if opts and opts.series then
    only = {}
    for _, s in ipairs(opts.series) do
      only[s] = true
    end
  end
  local changes = {}
  local function walk(list, link_of, migrate)
    for i, it in ipairs(list) do
      local want = {
        previous = M.value(root, it.file, link_of(list[i - 1])),
        next = M.value(root, it.file, link_of(list[i + 1])),
      }
      plan_note(it.file, want, migrate, changes)
    end
  end
  if cfg.daily.links and not only then
    local daily = require("logpose.notes.daily")
    local notes = vim.tbl_map(function(d)
      return { file = daily.path(d, root), label = M.daily_label(d) }
    end, daily.dates(root))
    walk(notes, function(n)
      return n
    end, false)
  end
  if cfg.series.links then
    local series = {}
    for _, it in ipairs(require("logpose.index").build(root)) do
      if
        it.kind == "note"
        and it.file_type == "meeting"
        and it.series
        and it.date
        and (not only or only[it.series])
      then
        series[it.series] = series[it.series] or {}
        table.insert(series[it.series], it)
      end
    end
    for _, list in pairs(series) do
      table.sort(list, function(a, b)
        if a.date ~= b.date then
          return a.date < b.date
        end
        return a.file < b.file
      end)
      walk(list, M.meeting_link, true)
    end
  end
  table.sort(changes, function(a, b)
    return a.path < b.path
  end)
  return changes
end

--- `:Logpose relink[!]`: add or fix the previous/next links everywhere (notes made before they
--- existed, a note deleted from the middle). Shows what changes and asks first; [!] doesn't.
---@param opts logpose.CommandOpts
function M.command(opts)
  local ui = require("logpose.util.ui")
  require("logpose.config").with_root(ui.safely(function(root)
    require("logpose.maintenance").confirm_and_apply(
      root,
      M.plan(root),
      "Relink daily notes and meeting series",
      opts.bang
    )
  end))
end

return M

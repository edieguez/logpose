--- Previous and next links between notes that follow each other: daily notes, by date, and the
--- meetings of a series. They're links in the frontmatter (`previous:`, `next:`): a new note gets
--- both, and its neighbours are pointed at it.
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

return M

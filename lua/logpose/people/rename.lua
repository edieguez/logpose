--- `:Logpose rename-person[!] handle New Name`: a person's new name everywhere. Their page moves
--- (`people/<new>.md`, links follow) and keeps the old name as an alias; attendees and `with:`
--- that name them by the old name, and `@old` mentions, are rewritten. Preview first (`!` skips
--- it); files with unsaved changes are never touched.
local config = require("logpose.config")
local fs = require("logpose.util.fs")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

--- The frontmatter keys holding people.
local KEYS = { attendees = true, with = true }

--- Plan the rename of the person `old` (any of their names) to `new`.
---@param root string
---@param old string
---@param new string
---@return logpose.Change[] changes, logpose.Person person
function M.plan(root, old, new)
  local people = require("logpose.people")
  local index = require("logpose.index")
  local fmw = require("logpose.frontmatter")
  local link = require("logpose.link")
  local maintenance = require("logpose.maintenance")
  new = vim.trim(new or "")
  local new_slug = text.slugify(new)
  if new_slug == "" then
    error("logpose: the new name needs letters or digits", 0)
  end
  local p = people.find(people.known(root), old)
  if not p then
    error(("logpose: nobody called %q"):format(old), 0)
  end
  if new == p.name then
    error("logpose: that's already their name", 0)
  end
  -- the names rewritten: the one being replaced, as written or as a handle
  local replaced = { [text.slugify((old:gsub("^@", "")))] = true, [text.slugify(p.name)] = true, [p.slug] = true }

  local moves, link_pairs = {}, {}
  local page_new = p.page and people.page_path(root, new)
  if p.page and page_new ~= p.page then
    if fs.exists(page_new) then
      error(("logpose: %s already exists"):format(link.relpath(root, page_new)), 0)
    end
    moves[p.page] = page_new
    table.insert(link_pairs, {
      (link.relpath(root, p.page):gsub("%.md$", "")),
      (link.relpath(root, page_new):gsub("%.md$", "")),
    })
  end

  local changes = {}
  for _, path in ipairs(index.files(root)) do
    local lines = fs.read_lines(path) or {}
    local close = fmw.close(lines)
    local count = 0
    if close then
      local values = index.frontmatter(vim.list_slice(lines, 1, close))
      local had_aliases = false
      local i = 2
      while i < close do
        local key = lines[i]:match("^(%w+):")
        local last = i
        while last + 1 < close and lines[last + 1]:match("^%s+%-") do
          last = last + 1 -- a block list's items
        end
        local v = key and values[key]
        if path == p.page and key == "name" then
          lines[i], count = fmw.line("name", new), count + 1
        elseif path == p.page and key == "aliases" then
          had_aliases = true
          local list = type(v) == "table" and v or (type(v) == "string" and v ~= "" and { v } or {})
          if not vim.tbl_contains(list, p.name) then
            list = vim.list_extend(vim.deepcopy(list), { p.name })
          end
          for k = last, i + 1, -1 do
            table.remove(lines, k)
          end
          close = close - (last - i)
          lines[i], count, last = fmw.line("aliases", list), count + 1, i
        elseif key and KEYS[key] and v then
          local list = type(v) == "table" and v or { v }
          local changed = false
          list = vim.tbl_map(function(name)
            if type(name) == "string" and replaced[text.slugify(name)] then
              changed = true
              return new
            end
            return name
          end, list)
          if changed then
            for k = last, i + 1, -1 do
              table.remove(lines, k)
            end
            close = close - (last - i)
            last = i
            lines[i] = fmw.line(key, type(v) == "table" and list or list[1])
            count = count + 1
          end
        end
        i = last + 1
      end
      if path == p.page and not had_aliases then
        table.insert(lines, close, fmw.line("aliases", { p.name }))
        close, count = close + 1, count + 1
      end
    end
    for k = (close or 0) + 1, #lines do
      local line = lines[k]
      local n = 0
      line = (" " .. line)
        :gsub("([%s%(%[,;])@(" .. text.HANDLE .. ")", function(pre, handle)
          local trail = handle:match("[%.%-]+$") or ""
          local name = handle:sub(1, #handle - #trail)
          if replaced[text.slugify(name)] then
            n = n + 1
            return pre .. "@" .. new_slug .. trail
          end
        end)
        :sub(2)
      local moved
      line, moved = maintenance.rewrite_links(line, link_pairs)
      lines[k] = line
      count = count + n + moved
    end
    if count > 0 then
      table.insert(changes, { path = path, content = table.concat(lines, "\n"), count = count })
    end
  end
  for from, to in pairs(moves) do
    table.insert(changes, { path = from, move_to = to, count = 0 })
  end
  table.sort(changes, function(a, b)
    return a.path < b.path
  end)
  return changes, p
end

--- Rename someone; `after` runs once it's done.
---@param old string
---@param new string
---@param opts? { bang?: boolean, after?: fun() }
function M.rename(old, new, opts)
  opts = opts or {}
  config.with_root(ui.safely(function(root)
    local changes, p = M.plan(root, old, new)
    require("logpose.maintenance").confirm_and_apply(
      root,
      changes,
      ("Rename %s → %s"):format(p.name, vim.trim(new)),
      opts.bang,
      opts.after
    )
  end))
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local old = opts.args[1]
  local new = table.concat(vim.list_slice(opts.args, 2), " ")
  if not old then
    error("logpose: usage :Logpose rename-person[!] handle New Name", 0)
  end
  if new ~= "" then
    return M.rename(old, new, { bang = opts.bang })
  end
  local people = require("logpose.people")
  local p = people.find(people.known(), old)
  if not p then
    error(("logpose: nobody called %q"):format(old), 0)
  end
  vim.ui.input(
    { prompt = ("New name for %s: "):format(p.name), default = p.name },
    ui.safely(function(input)
      if input and vim.trim(input) ~= "" and vim.trim(input) ~= p.name then
        M.rename(p.slug, input, { bang = opts.bang })
      end
    end)
  )
end

---@param arglead string
---@param args string[]
function M.complete(arglead, args)
  if #args > 0 then
    return {}
  end
  return require("logpose.lists.people").complete_person(arglead)
end

return M

--- People: a page per person (`people/<slug>.md`: name, aliases, role, projects, ways to reach
--- them, and your notes), merged with everyone your journal mentions (attendees, 1:1s, @mentions).
--- Aliases make "Ana", `@ana` and "Ana López" one person. Matching is forgiving: any part of the
--- name or an alias, accents ignored, the people you meet most (in this project, first) ahead.
local config = require("logpose.config")
local text = require("logpose.util.text")

local M = {}

---@class logpose.Person
---@field slug string        the page's file name, or the name's slug for someone without a page
---@field name string
---@field aliases string[]
---@field role? string
---@field count integer      notes, to-dos and lines involving them
---@field projects table<string, integer>  involvement per project (a page's `projects` count too)
---@field contacts table<string, string>   contact key -> value (`email`, `slack`…)
---@field page? string       path of their page
---@field slugs table<string, boolean>     every slug that means them (name, aliases, file)

-- Latin letters with accents, as plain ASCII.
local PLAIN = {}
for _, group in ipairs({
  { "a", "áàâäãåÁÀÂÄÃÅ" },
  { "e", "éèêëÉÈÊË" },
  { "i", "íìîïÍÌÎÏ" },
  { "o", "óòôöõøÓÒÔÖÕØ" },
  { "u", "úùûüÚÙÛÜ" },
  { "n", "ñÑ" },
  { "c", "çÇ" },
  { "y", "ýÿÝ" },
}) do
  for ch in group[2]:gmatch("[\192-\223][\128-\191]") do
    PLAIN[ch] = group[1]
  end
end

--- Lowercase, without accents: what matching compares.
---@param s string
---@return string
function M.plain(s)
  return (s:gsub("[\192-\223][\128-\191]", function(ch)
    return PLAIN[ch]
  end):lower())
end

--- The keys of a person's page that are theirs (not ways to reach them).
M.OWN = { "name", "aliases", "role", "projects" }

--- Configured ways to reach people, in order: { key, label, show, open }.
---@return { key: string, label: string, show?: string, open?: string }[]
function M.contact_kinds()
  local out = {}
  for key, c in pairs(config.get().people.contacts) do
    if c then
      table.insert(out, { key = key, label = c.label or key, show = c.show, open = c.open, order = c.order })
    end
  end
  table.sort(out, function(a, b)
    local oa, ob = a.order or math.huge, b.order or math.huge
    if oa ~= ob then
      return oa < ob
    end
    return a.key < b.key
  end)
  return out
end

--- A person's ways to reach them, in the configured order (others after, by key):
--- { key, label, value, shown, url }.
---@param p logpose.Person
---@return { key: string, label: string, value: string, shown: string, url?: string }[]
function M.contacts_of(p)
  local out, seen = {}, {}
  local template = require("logpose.template")
  for _, k in ipairs(M.contact_kinds()) do
    local v = p.contacts[k.key]
    if v and v ~= "" then
      seen[k.key] = true
      table.insert(out, {
        key = k.key,
        label = k.label,
        value = v,
        shown = k.show and template.substitute(k.show, { value = v }) or v,
        url = k.open and template.substitute(k.open, { value = v }) or nil,
      })
    end
  end
  local rest = {}
  for key, v in pairs(p.contacts) do
    if not seen[key] and v ~= "" then
      table.insert(rest, { key = key, label = key, value = v, shown = v })
    end
  end
  table.sort(rest, function(a, b)
    return a.key < b.key
  end)
  return vim.list_extend(out, rest)
end

--- A list value from frontmatter (a list, or a comma-separated string).
---@param v any
---@return string[]
local function list(v)
  if type(v) == "table" then
    return v
  elseif type(v) == "string" and v ~= "" then
    return vim.tbl_map(vim.trim, vim.split(v, ",", { trimempty = true }))
  end
  return {}
end

--- People with a page, from the index.
---@param items logpose.Item[]
---@return logpose.Person[]
function M.pages(items)
  local out = {}
  local own = {}
  for _, k in ipairs(M.OWN) do
    own[k] = true
  end
  for _, it in ipairs(items) do
    if it.kind == "person" then
      local fm = it.fields or {}
      local slug = vim.fn.fnamemodify(it.file, ":t:r")
      local name = type(fm.name) == "string" and fm.name ~= "" and fm.name or it.title or slug
      local p = {
        slug = slug,
        name = name,
        aliases = list(fm.aliases),
        role = type(fm.role) == "string" and fm.role ~= "" and fm.role or nil,
        count = 0,
        projects = {},
        contacts = {},
        page = it.file,
        slugs = { [slug] = true, [text.slugify(name)] = true },
      }
      for _, a in ipairs(p.aliases) do
        local s = text.slugify((a:gsub("^@", "")))
        if s ~= "" then
          p.slugs[s] = true
        end
      end
      for _, project in ipairs(list(fm.projects)) do
        p.projects[project:lower()] = 1
      end
      for key, v in pairs(fm) do
        if not own[key] and type(v) == "string" and v ~= "" and key ~= "created" and key ~= "modified" then
          p.contacts[key] = v
        end
      end
      table.insert(out, p)
    end
  end
  return out
end

--- Everyone: people with a page, and the people your journal mentions (merged into a page when a
--- name or alias matches), most involved first.
---@param root? string
---@return logpose.Person[]
function M.known(root)
  root = root or config.resolve_root()
  if not root then
    return {}
  end
  local items = require("logpose.index").build(root)
  local out = M.pages(items)
  local by_slug = {}
  for _, p in ipairs(out) do
    for s in pairs(p.slugs) do
      by_slug[s] = by_slug[s] or p
    end
  end
  local names = {}
  for _, item in ipairs(items) do
    for slug, name in pairs(item.names or {}) do
      names[slug] = names[slug] or name
    end
  end
  for _, item in ipairs(items) do
    for _, slug in ipairs(item.people or {}) do
      local p = by_slug[slug]
      if not p then
        p = {
          slug = slug,
          name = names[slug] or slug,
          aliases = {},
          count = 0,
          projects = {},
          contacts = {},
          slugs = { [slug] = true },
        }
        by_slug[slug] = p
        table.insert(out, p)
      end
      p.count = p.count + 1
      if item.project then
        p.projects[item.project] = (p.projects[item.project] or 0) + 1
      end
    end
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.slug < b.slug
  end)
  return out
end

--- The person a name, alias or handle means (nil when nobody).
---@param people logpose.Person[]
---@param name string
---@return logpose.Person?
function M.find(people, name)
  local s = text.slugify((vim.trim(name or ""):gsub("^@", "")))
  if s == "" then
    return nil
  end
  for _, p in ipairs(people) do
    if p.slugs[s] then
      return p
    end
  end
  return nil
end

--- Every slug that means the same person as `slug` (itself when unknown): for `person:` filters.
---@param slug string
---@return table<string, boolean>
function M.expand(slug)
  local p = M.find(M.known(), slug)
  return p and p.slugs or { [slug] = true }
end

--- People matching `query`, best first: the name, a handle or an alias starting with it, then a
--- word of the name, then containing it; accents and case ignored. Within that, the people of
--- `project` first, then the most involved. An empty query matches everyone.
---@param people logpose.Person[]
---@param query string
---@param project? string
---@return logpose.Person[]
function M.match(people, query, project)
  local q = M.plain(vim.trim(query or ""):gsub("^@", ""))
  local scored = {}
  for i, p in ipairs(people) do
    local name = M.plain(p.name)
    local rank
    if q == "" or vim.startswith(name, q) or vim.startswith(p.slug, q) then
      rank = 1
    else
      for _, a in ipairs(p.aliases) do
        if vim.startswith(M.plain((a:gsub("^@", ""))), q) then
          rank = 1
        end
      end
      if not rank then
        for word in name:gmatch("[^%s%.%-_]+") do
          if vim.startswith(word, q) then
            rank = 2
            break
          end
        end
      end
      if not rank and (name:find(q, 1, true) or p.slug:find(q, 1, true)) then
        rank = 3
      end
    end
    if rank then
      local here = project and p.projects[project] or 0
      table.insert(scored, { p = p, rank = rank, here = here, i = i })
    end
  end
  table.sort(scored, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    if (a.here > 0) ~= (b.here > 0) then
      return a.here > 0
    end
    if a.here ~= b.here then
      return a.here > b.here
    end
    return a.i < b.i
  end)
  return vim.tbl_map(function(s)
    return s.p
  end, scored)
end

--- A short description of a person for a completion menu: role, first way to reach them, how
--- often they come up.
---@param p logpose.Person
---@return string
function M.describe(p)
  local parts = {}
  if p.role then
    table.insert(parts, p.role)
  end
  local c = M.contacts_of(p)[1]
  if c then
    table.insert(parts, c.shown)
  end
  if p.count > 0 then
    table.insert(parts, ("%d note%s"):format(p.count, p.count == 1 and "" or "s"))
  end
  return table.concat(parts, " · ")
end

--- Completion for a name, or the last name in a comma-separated list ('customlist').
---@param arglead string
---@return string[]
function M.complete(arglead)
  local base, partial = arglead:match("^(.*,%s*)(.-)$")
  if not base then
    base, partial = "", arglead
  end
  local known = M.known()
  local have = {}
  for name in base:gmatch("[^,]+") do
    local p = M.find(known, name)
    if p then
      have[p] = true
    end
  end
  local out = {}
  for _, p in ipairs(M.match(known, partial, require("logpose.project").current())) do
    if not have[p] then
      table.insert(out, base .. p.name)
    end
  end
  return out
end

_G.LogposeCompletePeople = function(arglead)
  return M.complete(arglead)
end

--- The person named under the cursor: an `@mention`, or a name on a frontmatter `attendees:` /
--- `with:` line. Returns the name as written.
---@param bufnr integer
---@param row integer 1-based
---@param col integer 0-based byte column
---@return string?
function M.at(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local c = col + 1
  for s, handle, e in line:gmatch("()@(" .. text.HANDLE .. ")()") do
    if c >= s and c < e and (s == 1 or line:sub(s - 1, s - 1):match("[%s%(%[,;]")) then
      return (handle:gsub("[%.%-]+$", ""))
    end
  end
  local key, rest_at = line:match("^(%w+):%s*()")
  if (key ~= "attendees" and key ~= "with") or c < rest_at then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  if lines[1] ~= "---" or row == 1 then
    return nil
  end
  for i = 2, row - 1 do
    if lines[i] == "---" then
      return nil -- below the frontmatter
    end
  end
  local start = rest_at
  for i = rest_at, #line + 1 do
    local ch = line:sub(i, i)
    if ch == "," or ch == "]" or i == #line + 1 then
      if c >= start and c < i then
        local name = vim.trim((line:sub(start, i - 1):gsub("[%[%]\"']", "")))
        return name ~= "" and name or nil
      end
      start = i + 1
    end
  end
  return nil
end

--- Where a person's page goes.
---@param root string
---@param name string
---@return string? path
function M.page_path(root, name)
  local slug = text.slugify(name)
  return slug ~= "" and require("logpose.util.fs").join(config.path("people", root), slug .. ".md") or nil
end

--- Create a person's page from `v` (name, aliases, role, projects, contacts). Returns its path
--- and where the cursor goes (below the frontmatter, where your notes about them go).
---@param root string
---@param v table<string, any>
---@return string path, integer[] cursor
function M.create(root, v)
  local fs = require("logpose.util.fs")
  local fm = require("logpose.frontmatter")
  local name = vim.trim(v.name or "")
  local path = M.page_path(root, name)
  if not path then
    error(("logpose: can't make a filename from %q"):format(name), 0)
  end
  if fs.exists(path) then
    error(("logpose: %s already exists"):format(require("logpose.link").relpath(root, path)), 0)
  end
  local lines = { "---", fm.line("name", name) }
  for _, key in ipairs({ "aliases", "role", "projects" }) do
    local val = v[key]
    if val ~= nil and val ~= "" and not (type(val) == "table" and #val == 0) then
      table.insert(lines, fm.line(key, val))
    end
  end
  for _, k in ipairs(M.contact_kinds()) do
    local val = v[k.key]
    if type(val) == "string" and val ~= "" then
      table.insert(lines, fm.line(k.key, val))
    end
  end
  vim.list_extend(lines, require("logpose.timestamps").lines())
  table.insert(lines, "---")
  table.insert(lines, "") -- your notes about them go here
  local ok, err = fs.write_file(path, table.concat(lines, "\n") .. "\n")
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  return path, { #lines, 0 }
end

return M

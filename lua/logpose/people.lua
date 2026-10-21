--- People: names from attendees, 1:1s (`with:`) and @mentions, read from the index, plus an
--- optional list you keep (`people.file`, `people.md` in the journal) so people are known before
--- your first meeting with them. Matching is forgiving: any part of the name, accents ignored,
--- the people you meet most (in this project, first) ahead.
local config = require("logpose.config")
local text = require("logpose.util.text")

local M = {}

---@class logpose.Person
---@field slug string
---@field name string        as written (the list's spelling wins)
---@field count integer      notes, to-dos and lines involving them
---@field projects table<string, integer>  involvement per project (a list's #tags count too)
---@field email? string
---@field listed? boolean    in the people list

-- Latin letters with accents, as plain ASCII (UTF-8 sequences).
local PLAIN = {
  ["á"] = "a",
  ["à"] = "a",
  ["â"] = "a",
  ["ä"] = "a",
  ["ã"] = "a",
  ["å"] = "a",
  ["Á"] = "a",
  ["À"] = "a",
  ["Â"] = "a",
  ["Ä"] = "a",
  ["Ã"] = "a",
  ["Å"] = "a",
  ["é"] = "e",
  ["è"] = "e",
  ["ê"] = "e",
  ["ë"] = "e",
  ["É"] = "e",
  ["È"] = "e",
  ["Ê"] = "e",
  ["Ë"] = "e",
  ["í"] = "i",
  ["ì"] = "i",
  ["î"] = "i",
  ["ï"] = "i",
  ["Í"] = "i",
  ["Ì"] = "i",
  ["Î"] = "i",
  ["Ï"] = "i",
  ["ó"] = "o",
  ["ò"] = "o",
  ["ô"] = "o",
  ["ö"] = "o",
  ["õ"] = "o",
  ["ø"] = "o",
  ["Ó"] = "o",
  ["Ò"] = "o",
  ["Ô"] = "o",
  ["Ö"] = "o",
  ["Õ"] = "o",
  ["Ø"] = "o",
  ["ú"] = "u",
  ["ù"] = "u",
  ["û"] = "u",
  ["ü"] = "u",
  ["Ú"] = "u",
  ["Ù"] = "u",
  ["Û"] = "u",
  ["Ü"] = "u",
  ["ñ"] = "n",
  ["Ñ"] = "n",
  ["ç"] = "c",
  ["Ç"] = "c",
  ["ý"] = "y",
  ["ÿ"] = "y",
  ["Ý"] = "y",
}

--- Lowercase, without accents: what matching compares.
---@param s string
---@return string
function M.plain(s)
  return (s:gsub("[\192-\223][\128-\191]", function(ch)
    return PLAIN[ch]
  end):lower())
end

--- The people list file of the journal.
---@param root string
---@return string
function M.list_path(root)
  return require("logpose.util.fs").join(root, config.get().people.file)
end

--- People in the list: `- Name (email) #project …`, one per list item.
---@param root string
---@return logpose.Person[]
function M.from_list(root)
  local lines = require("logpose.util.fs").read_lines(M.list_path(root)) or {}
  local out = {}
  for _, line in ipairs(lines) do
    local item = line:match("^%s*[-*+]%s+(.+)$")
    if item and not item:match("^%[") then
      local email = item:match("%(([^%)]*@[^%)]*)%)") or item:match("<([^>]*@[^>]*)>")
      local name = vim.trim((item:gsub("%b()", ""):gsub("%b<>", ""):gsub("%s#[%w_%-/]+", ""):gsub("^#[%w_%-/]+", "")))
      name = name:gsub("^@", "")
      local slug = text.slugify(name)
      if slug ~= "" then
        local projects = {}
        for tag in (" " .. item):gmatch("%s#([%w_][%w_%-/]*)") do
          projects[tag:lower()] = 1
        end
        table.insert(out, { slug = slug, name = name, count = 0, projects = projects, email = email, listed = true })
      end
    end
  end
  return out
end

--- Known people: the index's and the list's, most involved first.
---@param root? string
---@return logpose.Person[]
function M.known(root)
  root = root or config.resolve_root()
  if not root then
    return {}
  end
  local by_slug, out = {}, {}
  local function get(slug, name)
    local p = by_slug[slug]
    if not p then
      p = { slug = slug, name = name or slug, count = 0, projects = {} }
      by_slug[slug] = p
      table.insert(out, p)
    end
    return p
  end
  local names = {}
  for _, item in ipairs(require("logpose.index").build(root)) do
    for slug, name in pairs(item.names or {}) do
      names[slug] = names[slug] or name
    end
    for _, slug in ipairs(item.people or {}) do
      local p = get(slug)
      p.count = p.count + 1
      if item.project then
        p.projects[item.project] = (p.projects[item.project] or 0) + 1
      end
    end
  end
  for _, p in ipairs(out) do
    p.name = names[p.slug] or p.name
  end
  for _, l in ipairs(M.from_list(root)) do
    local p = get(l.slug, l.name)
    p.name, p.email, p.listed = l.name, l.email, true -- the list's spelling wins
    for project in pairs(l.projects) do
      p.projects[project] = (p.projects[project] or 0) + 1
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

--- People matching `query`, best first: a name starting with it, then a word of the name (or
--- the handle) starting with it, then containing it; accents and case ignored. Within that, the
--- people of `project` first, then the most involved. An empty query matches everyone.
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
      for word in name:gmatch("[^%s%.%-_]+") do
        if vim.startswith(word, q) then
          rank = 2
          break
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

--- A short description of a person for a completion menu: how often, and where.
---@param p logpose.Person
---@return string
function M.describe(p)
  local parts = {}
  if p.count > 0 then
    table.insert(parts, ("%d note%s"):format(p.count, p.count == 1 and "" or "s"))
  elseif p.listed then
    table.insert(parts, "people list")
  end
  local projects = vim.tbl_keys(p.projects)
  table.sort(projects)
  if #projects > 0 then
    table.insert(parts, table.concat(projects, ", "))
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
  local have = {}
  for name in base:gmatch("[^,]+") do
    have[text.slugify(vim.trim(name))] = true
  end
  local out = {}
  for _, p in ipairs(M.match(M.known(), partial, require("logpose.project").current())) do
    if not have[p.slug] then
      table.insert(out, base .. p.name)
    end
  end
  return out
end

_G.LogposeCompletePeople = function(arglead)
  return M.complete(arglead)
end

return M

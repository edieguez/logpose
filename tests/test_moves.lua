-- Every move logpose makes keeps every link working, in both link styles: links to the moved note,
-- links in it (a markdown link is relative to the note it's in) and links between notes moving
-- together. Each link is checked by its path, and must lead to the note its label names.
local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      H.freeze(child, 2026, 10, 15)
    end,
    post_once = child.stop,
  },
})

-- In the child: `seed(root, style)` writes a journal whose notes link to each other every way a move
-- can affect (same folder, a parent's, across the journal, frontmatter previous/next), each link
-- labelled with its target's title; `broken(root)` lists the links that don't lead, by their path,
-- to the note their label names (a renamed person's old name, kept as an alias, counts).
local JOURNAL = [==[
local function rel(root, path)
  return require("logpose.link").relpath(root, path)
end
local function resolve(dir, path)
  local out = vim.split(dir, "/", { trimempty = true })
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      table.remove(out)
    elseif part ~= "." then
      table.insert(out, part)
    end
  end
  return "/" .. table.concat(out, "/")
end

_G.seed = function(root, style)
  require("logpose").setup({ root = root, link_style = style, picker = "select", timestamps = { created = false, modified = false } })
  local link, fmt = require("logpose.link"), require("logpose.frontmatter")
  local function p(path) return root .. "/" .. path end
  local retro1, retro15 = "meetings/acme/2026-10-01 - retro.md", "meetings/acme/2026-10-15 - retro.md"
  -- path, frontmatter, the notes it links to, its previous/next
  local notes = {
    { "notes/queue-design.md", { title = "Queue design" },
      { "projects/acme.md", "projects/acme/use-postgres.md", retro15, "tasks/ship-it.md", "people/ana.md" } },
    { "projects/acme.md", { title = "Acme page", project = "acme" }, { "notes/queue-design.md", "projects/acme/use-postgres.md" } },
    { "projects/beta.md", { title = "Beta page", project = "beta" }, {} },
    { "projects/acme/use-postgres.md", { title = "Use Postgres", type = "decision", status = "accepted" },
      { "projects/acme/deploy.md", "projects/acme.md", "notes/queue-design.md" } },
    { "projects/acme/deploy.md", { title = "Deploy", type = "runbook" }, { "projects/acme/use-postgres.md" } },
    { retro1, { title = "Retro 1", type = "retro", date = "2026-10-01", project = "acme", series = "acme/retro" },
      { "projects/acme.md" }, { next = retro15 } },
    { retro15, { title = "Retro 15", type = "retro", date = "2026-10-15", project = "acme", series = "acme/retro" },
      { "projects/acme.md", "notes/queue-design.md" }, { previous = retro1 } },
    { "meetings/2026-10-05 - sync.md", { title = "Sync", type = "adhoc", date = "2026-10-05" }, { "notes/queue-design.md", retro1 } },
    { "daily/daily-2026-10-15.md", { title = "Daily" }, { retro15, "tasks/ship-it.md" } },
    { "tasks/ship-it.md", { title = "Ship it", status = "done", done = "2026-10-02" }, { "notes/queue-design.md" } },
    { "people/ana.md", { name = "Ana" }, { "people/bob.md", "notes/queue-design.md" } },
    { "people/bob.md", { name = "Bob" }, { "people/ana.md" } },
  }
  local title = {}
  for _, n in ipairs(notes) do
    title[n[1]] = n[2].title or n[2].name
  end
  for _, n in ipairs(notes) do
    local file = p(n[1])
    local lines = { "---" }
    for _, k in ipairs({ "title", "name", "type", "status", "date", "done", "project", "series" }) do
      if n[2][k] then
        table.insert(lines, fmt.line(k, n[2][k]))
      end
    end
    for _, k in ipairs({ "previous", "next" }) do
      local to = (n[4] or {})[k]
      if to then
        table.insert(lines, fmt.line(k, link.make(file, p(to), title[to], root)))
      end
    end
    table.insert(lines, "---")
    for _, to in ipairs(n[3]) do
      table.insert(lines, "- " .. link.make(file, p(to), title[to], root))
    end
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.fn.writefile(lines, file)
  end
  require("logpose.index").flush()
end

_G.broken = function(root)
  local index, fs = require("logpose.index"), require("logpose.util.fs")
  local base = fs.join(root, require("logpose.config").get().link_base)
  local function names(file)
    local fm = index.frontmatter(vim.fn.readfile(file))
    local out = {}
    for _, k in ipairs({ "title", "name" }) do
      if type(fm[k]) == "string" then
        out[fm[k]] = true
      end
    end
    for _, a in ipairs(type(fm.aliases) == "table" and fm.aliases or {}) do
      out[a] = true
    end
    return out
  end
  local bad = {}
  for _, file in ipairs(index.files(root)) do
    for _, l in ipairs(vim.fn.readfile(file)) do
      local found = {}
      for target, label in l:gmatch("%[%[([^|%]]+)|([^%]]+)%]%]") do
        table.insert(found, { label, fs.join(base, target:match("%.md$") and target or (target .. ".md")) })
      end
      for label, dest in l:gmatch("%[([^%[%]]*)%]%((.-)%)") do
        local path = (dest:match("^<(.-)>") or dest:match("^(%S+)")):gsub("#.*$", "")
        path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        table.insert(found, { label, resolve(vim.fs.dirname(file), path) })
      end
      for _, f in ipairs(found) do
        if not (vim.uv.fs_stat(f[2]) and names(f[2])[f[1]]) then
          table.insert(bad, ("%s: %s -> %s"):format(rel(root, file), f[1], rel(root, f[2])))
        end
      end
    end
  end
  table.sort(bad)
  return bad
end
]==]

local function seed(style)
  child.lua(JOURNAL)
  child.lua(("_G.seed(%q, %q)"):format(root, style))
  eq(child.lua_get(("_G.broken(%q)"):format(root)), {}) -- every link works to begin with
end

local function broken()
  return child.lua_get(("_G.broken(%q)"):format(root))
end

local function apply(plan)
  child.lua(("require('logpose.maintenance').apply(%s)"):format(plan))
end

T["every link still works after"] = MiniTest.new_set({ parametrize = { { "wiki" }, { "markdown" } } })
local moves = T["every link still works after"]

moves["archiving a project, and restoring it"] = function(style)
  seed(style)
  child.lua(("require('logpose.project').set_archived(%q, 'acme', true)"):format(root))
  eq(vim.fn.filereadable(root .. "/projects/archive/acme/use-postgres.md"), 1)
  eq(broken(), {})
  child.lua(("require('logpose.project').set_archived(%q, 'acme', false)"):format(root))
  eq(vim.fn.filereadable(root .. "/projects/acme/use-postgres.md"), 1)
  eq(broken(), {})
end

moves["renaming a project"] = function(style)
  seed(style)
  apply(("require('logpose.maintenance').plan_project(%q, 'acme', 'acme-web')"):format(root))
  eq(vim.fn.filereadable(root .. "/projects/acme-web/deploy.md"), 1)
  eq(broken(), {})
end

moves["merging a project into another"] = function(style)
  seed(style)
  apply(("require('logpose.maintenance').plan_project(%q, 'acme', 'beta', { merge = true })"):format(root))
  eq(vim.fn.filereadable(root .. "/meetings/beta/2026-10-15 - retro.md"), 1)
  eq(broken(), {})
end

moves["promoting a doc to a lasting note"] = function(style)
  seed(style)
  child.lua(("require('logpose.notes.doc').promote(%q, %q)"):format(root, root .. "/projects/acme/use-postgres.md"))
  eq(vim.fn.filereadable(root .. "/notes/use-postgres.md"), 1)
  eq(broken(), {})
end

moves["moving a doc to another project"] = function(style)
  seed(style)
  child.lua(("require('logpose.notes.doc').move(%q, %q, 'beta')"):format(root, root .. "/projects/acme/deploy.md"))
  eq(vim.fn.filereadable(root .. "/projects/beta/deploy.md"), 1)
  eq(broken(), {})
end

moves["moving a meeting to another project, and one with no project into one"] = function(style)
  seed(style)
  child.lua(
    ("require('logpose.edit.save').move_meeting(%q, %q, 'acme', 'beta')"):format(
      root,
      root .. "/meetings/acme/2026-10-15 - retro.md"
    )
  )
  eq(vim.fn.filereadable(root .. "/meetings/beta/2026-10-15 - retro.md"), 1)
  eq(broken(), {})
  child.lua(
    ("require('logpose.edit.save').move_meeting(%q, %q, nil, 'acme')"):format(
      root,
      root .. "/meetings/2026-10-05 - sync.md"
    )
  )
  eq(vim.fn.filereadable(root .. "/meetings/acme/2026-10-05 - sync.md"), 1)
  eq(broken(), {})
end

moves["renaming a person"] = function(style)
  seed(style)
  apply(("(require('logpose.people.rename').plan(%q, 'ana', 'Ana López'))"):format(root))
  eq(vim.fn.filereadable(root .. "/people/ana-lopez.md"), 1)
  eq(broken(), {})
end

moves[":Logpose archive (links to the task, and the task's own)"] = function(style)
  seed(style)
  child.cmd("Logpose archive!")
  eq(vim.fn.filereadable(root .. "/tasks/archive/week-2026-09-28/ship-it.md"), 1)
  eq(broken(), {})
  H.contains(
    child.notifications()[#child.notifications()].msg,
    "archived 1 done task; links to them updated in 2 notes"
  )
end

T["a markdown link keeps its form: <…>, %20, its #anchor and title; URLs and headings are left alone"] = function()
  child.lua(([[
    require('logpose').setup({ root = %q, link_style = 'markdown' })
    local m = require('logpose.maintenance')
    local root = %q
    local pairs = { m.link_pair(root, root .. '/meetings/acme/', root .. '/meetings/beta/'),
      m.link_pair(root, root .. '/notes/x.md', root .. '/notes/old/x.md') }
    local function rw(line, file) return (m.rewrite_links(line, pairs, root .. '/' .. file)) end
    _G.got = {
      rw('[R](<../meetings/acme/2026-10-15 - retro.md>)', 'daily/d.md'),
      rw('[R](../meetings/acme/2026-10-15%%20-%%20retro.md)', 'daily/d.md'),
      rw('[X](x.md#part "Its title")', 'notes/y.md'),
      rw('[site](https://example.com/notes/x.md) [top](#top)', 'notes/y.md'),
      rw('![diagram](../../projects/d.png)', 'meetings/acme/m.md'),
      rw('[Y](y.md)', 'notes/x.md'),
      rw('[R](<2026-10-01 - retro.md>)', 'meetings/acme/m.md'),
    }
  ]]):format(root, root))
  eq(child.lua_get("_G.got"), {
    "[R](<../meetings/beta/2026-10-15 - retro.md>)",
    "[R](../meetings/beta/2026-10-15%20-%20retro.md)",
    '[X](old/x.md#part "Its title")',
    "[site](https://example.com/notes/x.md) [top](#top)",
    "![diagram](../../projects/d.png)", -- the note moves to meetings/beta/: same depth, same path
    "[Y](../y.md)", -- the note's own link, as it moves down a folder
    "[R](<2026-10-01 - retro.md>)", -- notes moving together keep the link between them
  })
end

return T

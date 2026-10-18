local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local function setup(extra)
  child.lua(
    ("require('logpose').setup(vim.tbl_extend('force', { root = %q, picker = 'select' }, %s))"):format(
      root,
      extra or "{}"
    )
  )
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      setup()
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function p(rel)
  return root .. "/" .. rel
end

T["views"] = MiniTest.new_set()

T["views"]["run saved searches by name or from a list"] = function()
  setup([[{ views = { acme = "tasks open project:acme", all = "notes" } }]])
  H.write(p("INBOX.md"), "# INBOX\n- [ ] a #acme\n- [ ] b\n")
  child.lua([[
    _G.offered = {}
    vim.ui.select = function(items, opts, cb)
      table.insert(_G.offered, { prompt = opts.prompt, labels = vim.tbl_map(opts.format_item or tostring, items) })
      if opts.prompt == "View" then return cb(items[1]) end
      cb(nil)
    end
  ]])
  child.cmd("Logpose view acme")
  eq(child.lua_get("_G.offered")[1], { prompt = "Tasks open project:acme", labels = { "[ ] a #acme  · INBOX" } })
  child.cmd("Logpose view")
  eq(child.lua_get("_G.offered")[2].labels, { "acme  (tasks open project:acme)", "all  (notes)" })
  eq(child.lua_get("_G.offered")[3].prompt, "Tasks open project:acme")
  eq(child.fn.getcompletion("Logpose view ", "cmdline"), { "acme", "all" })
end

T["views"]["unknown view and no views"] = function()
  child.cmd("Logpose view nope")
  H.contains(child.notifications()[1].msg, "unknown view")
  child.cmd("Logpose view")
  H.contains(child.notifications()[2].msg, "no views")
end

T["rename-tag"] = MiniTest.new_set()

local function stub_apply(choice)
  child.lua(
    ("vim.ui.select = function(items, opts, cb) _G.preview = vim.api.nvim_buf_get_lines(0, 0, -1, false); cb(%q) end"):format(
      choice
    )
  )
end

T["rename-tag"]["renames inline and frontmatter tags only"] = function()
  H.write(p("INBOX.md"), "# INBOX\n- [ ] a #perf, b (#Perf) #perfect #perf-\n")
  H.write(p("notes/x.md"), "---\ntitle: X\ntags: [perf, team]\n---\n# X #perf\n")
  H.write(p("notes/y.md"), "# Y\nnothing here\n")
  stub_apply("Apply")
  child.cmd("Logpose rename-tag perf performance")
  H.contains(table.concat(child.lua_get("_G.preview"), "\n"), "INBOX.md (3 changes)")
  eq(H.read(p("INBOX.md")), "# INBOX\n- [ ] a #performance, b (#performance) #perfect #performance-\n")
  eq(H.read(p("notes/x.md")), "---\ntitle: X\ntags: [performance, team]\n---\n# X #performance\n")
  eq(H.read(p("notes/y.md")), "# Y\nnothing here\n")
  H.contains(child.notifications()[1].msg, "updated 2 files")
end

T["rename-tag"]["cancel, bang, unsaved buffers, invalid names"] = function()
  H.write(p("INBOX.md"), "# INBOX\n- [ ] a #perf\n")
  stub_apply("Cancel")
  child.cmd("Logpose rename-tag perf speed")
  eq(H.read(p("INBOX.md")), "# INBOX\n- [ ] a #perf\n")
  child.cmd("Logpose rename-tag! #perf #speed")
  eq(H.read(p("INBOX.md")), "# INBOX\n- [ ] a #speed\n")
  child.cmd("edit " .. p("INBOX.md"))
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# INBOX!" })
  child.cmd("Logpose rename-tag! speed perf")
  H.contains(child.notifications()[#child.notifications()].msg, "unsaved changes")
  eq(H.read(p("INBOX.md")), "# INBOX\n- [ ] a #speed\n")
  child.cmd("Logpose rename-tag speed 'bad name'")
  H.contains(child.notifications()[#child.notifications()].msg, "usage")
  child.cmd("Logpose rename-tag nothing here")
  H.contains(child.notifications()[#child.notifications()].msg, "nothing to change")
end

T["rename-project moves the folder and page and fixes links"] = function()
  H.write(
    p("meetings/acme/2026-10-14 - retro.md"),
    '---\ntype: retro\nproject: acme\ntitle: "Retro"\nseries: acme/retro\n---\n# Retro\n- [ ] x #acme\n'
  )
  H.write(p("projects/acme.md"), '---\ntitle: "Acme"\ntype: project\nproject: acme\n---\n# Acme\n')
  H.write(p("projects/acme-api.md"), "# Acme API\n")
  H.write(
    p("daily/daily-2026-10-14.md"),
    "# day\n- acme: [[meetings/acme/2026-10-14 - retro|Retro]]\nsee [[projects/acme|Acme]] and [[projects/acme-api]]\n[r](../meetings/acme/2026-10-14 - retro.md)\n"
  )
  H.write(p("meetings/thesis/n.md"), "# n\n[r](<../acme/2026-10-14 - retro.md>)\n")
  H.write(p("INBOX.md"), "# INBOX\n- [ ] a #acme\n")
  child.cmd("Logpose project acme")
  child.cmd("Logpose rename-project! acme acme-web")
  eq(vim.fn.isdirectory(p("meetings/acme")), 0)
  H.contains(H.read(p("meetings/acme-web/2026-10-14 - retro.md")), "project: acme-web\n")
  H.contains(H.read(p("meetings/acme-web/2026-10-14 - retro.md")), "series: acme-web/retro\n")
  H.contains(H.read(p("meetings/acme-web/2026-10-14 - retro.md")), "- [ ] x #acme-web\n")
  eq(vim.fn.filereadable(p("projects/acme-web.md")), 1)
  eq(vim.fn.filereadable(p("projects/acme-api.md")), 1)
  eq(
    H.read(p("daily/daily-2026-10-14.md")),
    "# day\n- acme: [[meetings/acme-web/2026-10-14 - retro|Retro]]\nsee [[projects/acme-web|Acme]] and [[projects/acme-api]]\n[r](../meetings/acme-web/2026-10-14 - retro.md)\n"
  )
  eq(H.read(p("meetings/thesis/n.md")), "# n\n[r](<../acme-web/2026-10-14 - retro.md>)\n")
  eq(H.read(p("INBOX.md")), "# INBOX\n- [ ] a #acme-web\n")
  eq(child.lua_get("require('logpose').project()"), "acme-web")
end

T["rename-project refuses to overwrite"] = function()
  H.write(p("meetings/acme/a.md"), "# a\n")
  H.write(p("meetings/web/b.md"), "# b\n")
  child.cmd("Logpose rename-project! acme web")
  H.contains(child.notifications()[1].msg, "already exists")
  eq(vim.fn.filereadable(p("meetings/acme/a.md")), 1)
end

--- Pretend a file was last changed `secs` seconds ago.
local function age(path, secs)
  local t = os.time() - secs
  vim.uv.fs_utime(path, t, t)
end

T["index cache"] = function()
  H.write(p("a.md"), "# a\n- [ ] one\n")
  H.write(p("b.md"), "# b\n")
  age(p("a.md"), 10)
  age(p("b.md"), 10)
  child.lua(("require('logpose.index').build(%q)"):format(root))
  local reads = child.lua_get("require('logpose.index').reads")
  child.lua(("require('logpose.index').build(%q)"):format(root))
  eq(child.lua_get("require('logpose.index').reads"), reads)
  H.write(p("a.md"), "# a\n- [ ] one\n- [ ] two\n")
  local items = child.lua_get(("#require('logpose.index').build(%q)"):format(root))
  eq(child.lua_get("require('logpose.index').reads"), reads + 1)
  eq(items, 4)
  vim.fn.delete(p("b.md"))
  eq(child.lua_get(("#require('logpose.index').build(%q)"):format(root)), 3)
end

T["index: one build per command, unless something is written"] = function()
  H.write(p("a.md"), "# a\n")
  age(p("a.md"), 10)
  -- several builds in one go (one command) parse nothing new and return equal, separate lists
  eq(
    child.lua_get(([[(function()
      local index = require('logpose.index')
      local x = index.build(%q)
      table.insert(x, 'junk') -- a caller changing its list doesn't affect the next build
      local y = index.build(%q)
      return { #x, #y }
    end)()]]):format(root, root)),
    { 2, 1 }
  )
  -- a write in between is seen at once
  eq(
    child.lua_get(([[(function()
      local index = require('logpose.index')
      local before = #index.build(%q)
      require('logpose.util.fs').write_file(%q, '# b\n- [ ] new\n')
      return { before, #index.build(%q) }
    end)()]]):format(root, p("b.md"), root)),
    { 1, 3 }
  )
  -- a file changed behind logpose's back is seen by the next command
  H.write(p("c.md"), "# c\n")
  eq(child.lua_get(("#require('logpose.index').build(%q)"):format(root)), 4)
end

T["index cache: a file changed just now is read again until its timestamp is settled"] = function()
  H.write(p("a.md"), "# a\n")
  child.lua(("require('logpose.index').build(%q)"):format(root))
  local reads = child.lua_get("require('logpose.index').reads")
  -- same second, same size, new content: a coarse-mtime filesystem couldn't tell them apart
  H.write(p("a.md"), "# b\n")
  local st = vim.uv.fs_stat(p("a.md"))
  child.lua(("require('logpose.index').build(%q)"):format(root))
  eq(child.lua_get("require('logpose.index').reads"), reads + 1)
  H.contains(vim.inspect(child.lua_get(("require('logpose.index').build(%q)[1].title"):format(root))), "b")
  -- once the timestamp is old, the entry is trusted
  age(p("a.md"), 10)
  child.lua(("require('logpose.index').build(%q)"):format(root))
  reads = child.lua_get("require('logpose.index').reads")
  child.lua(("require('logpose.index').build(%q)"):format(root))
  eq(child.lua_get("require('logpose.index').reads"), reads)
  eq(st ~= nil, true)
end

return T

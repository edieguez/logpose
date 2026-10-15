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
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 14)
    end,
    post_once = child.stop,
  },
})

local function select_picks(...)
  child.lua(("_G.picks = %s"):format(vim.inspect({ ... })))
  child.lua([[
    _G.offered = {}
    vim.ui.select = function(items, opts, cb)
      local labels = vim.tbl_map(opts.format_item or tostring, items)
      table.insert(_G.offered, { prompt = opts.prompt, labels = labels })
      local want = table.remove(_G.picks, 1)
      for i, label in ipairs(labels) do
        if want and label:find(want, 1, true) then return cb(items[i]) end
      end
      cb(nil)
    end
  ]])
end

T["links_in"] = function()
  local links = child.lua_get([=[require('logpose.index').links_in(
    "see [[projects/acme|Acme]] and [[acme#goals]], [doc](../notes/x.md) [web](https://x.y) [a](<my note.md>)")]=])
  eq(links, {
    { target = "projects/acme", style = "wiki" },
    { target = "acme", style = "wiki" },
    { target = "../notes/x.md", style = "markdown" },
    { target = "my note.md", style = "markdown" },
  })
end

T[":Logpose note creates a topic note"] = function()
  child.cmd("Logpose note Queue design")
  local path = root .. "/notes/queue-design.md"
  eq(child.api.nvim_buf_get_name(0), path)
  eq(H.read(path), '---\ntitle: "Queue design"\ncreated: 2026-10-14\ntags: []\n---\n# Queue design\n\n\n')
  eq(child.api.nvim_win_get_cursor(0), { 8, 0 })
  child.cmd("Logpose project acme")
  child.cmd("Logpose note Retry policy")
  H.contains(H.read(root .. "/notes/retry-policy.md"), "project: acme\n")
  H.write(path, "# mine\n")
  child.cmd("Logpose note Queue design")
  eq(H.read(path), "# mine\n")
end

T[":Logpose note prompts without a title"] = function()
  child.lua("vim.ui.input = function(_, cb) cb('From prompt') end")
  child.cmd("Logpose note")
  eq(vim.fn.filereadable(root .. "/notes/from-prompt.md"), 1)
end

T[":Logpose project-page"] = function()
  child.cmd("Logpose project-page Acme API")
  local path = root .. "/projects/acme-api.md"
  H.contains(
    H.read(path),
    '---\ntitle: "Acme API"\ntype: project\nproject: acme-api\ntags: []\n---\n# Acme API\n\n## Overview\n'
  )
  child.cmd("Logpose project thesis")
  child.cmd("Logpose project-page")
  eq(vim.fn.filereadable(root .. "/projects/thesis.md"), 1)
end

T["backlinks and outgoing links"] = function()
  H.write(root .. "/projects/acme.md", '---\ntitle: "Acme"\ntype: project\n---\n# Acme\nSee [[notes/missing]]\n')
  H.write(root .. "/daily/daily-2026-10-14.md", "# day\n- talked about [[projects/acme|Acme]]\n")
  H.write(root .. "/meetings/2026-10-13 - retro.md", "# Retro\nSee [the project](../projects/acme.md)\n")
  H.write(root .. "/INBOX.md", "# INBOX\n- [ ] update [[acme]] page\n")
  child.cmd("edit " .. root .. "/projects/acme.md")
  select_picks("Retro")
  child.cmd("Logpose backlinks")
  local labels = child.lua_get("_G.offered")[1].labels
  table.sort(labels)
  eq(labels, {
    "INBOX: - [ ] update [[acme]] page",
    "Retro: See [the project](../projects/acme.md)",
    "day: - talked about [[projects/acme|Acme]]",
  })
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "2026-10-13 - retro.md")
  eq(child.api.nvim_win_get_cursor(0)[1], 2)

  child.cmd("edit " .. root .. "/projects/acme.md")
  select_picks()
  child.cmd("Logpose links")
  eq(child.lua_get("_G.offered")[1].labels, { "notes/missing  (missing)" })
end

T["no backlinks says so"] = function()
  H.write(root .. "/notes/alone.md", "# alone\n")
  child.cmd("edit " .. root .. "/notes/alone.md")
  child.cmd("Logpose backlinks")
  H.contains(child.notifications()[1].msg, "no backlinks")
end

T["[[ completion items replace the typed prefix with a link"] = function()
  H.write(root .. "/notes/queue-design.md", '---\ntitle: "Queue design"\n---\n# Queue design\n')
  H.write(root .. "/projects/acme.md", '---\ntitle: "Acme"\n---\n# Acme\n')
  local source = root .. "/daily/daily-2026-10-14.md"
  local items = child.lua_get(("require('logpose.links').complete_items('see [[qu', 9, 3, %q)"):format(source))
  eq(#items, 2)
  local q = vim.tbl_filter(function(i)
    return i.label == "Queue design"
  end, items)[1]
  eq(q.textEdit, {
    newText = "[[notes/queue-design|Queue design]]",
    range = { start = { line = 3, character = 4 }, ["end"] = { line = 3, character = 9 } },
  })
  eq(child.lua_get("require('logpose.links').complete_items('no link here', 12, 0, '')"), {})
  child.lua(("require('logpose').setup({ root = %q, link_style = 'markdown' })"):format(root))
  items = child.lua_get(("require('logpose.links').complete_items('[[', 2, 0, %q)"):format(source))
  local md = vim.tbl_filter(function(i)
    return i.label == "Acme"
  end, items)[1]
  eq(md.textEdit.newText, "[Acme](../projects/acme.md)")
end

T["nvim-cmp and blink.cmp sources"] = function()
  H.write(root .. "/notes/x.md", "# X\n")
  child.lua([[package.loaded["cmp"] = { register_source = function(name, src) _G.registered = { name, src } end }]])
  child.lua(("require('logpose').setup({ root = %q })"):format(root))
  eq(child.lua_get("_G.registered[1]"), "logpose")
  child.cmd("edit " .. root .. "/daily/daily-2026-10-14.md")
  child.bo.filetype = "markdown"
  eq(child.lua_get("_G.registered[2]:is_available()"), true)
  child.lua(
    [[_G.registered[2]:complete({ context = { cursor = { row = 1, col = 3 }, cursor_line = "[[", bufnr = 0 } }, function(r) _G.cmp_result = r end)]]
  )
  eq(child.lua_get("_G.cmp_result.items[1].label"), "X")
  child.lua([[
    local blink = require("logpose.completion.blink").new()
    _G.blink_enabled = blink:enabled()
    blink:get_completions({ cursor = { 1, 2 }, line = "[[", bufnr = 0 }, function(r) _G.blink_result = r end)
  ]])
  eq(child.lua_get("_G.blink_enabled"), true)
  eq(child.lua_get("_G.blink_result.items[1].label"), "X")
end

T["find topics lists notes and project pages"] = function()
  H.write(root .. "/notes/x.md", '---\ntitle: "X"\n---\n# X\n')
  H.write(root .. "/projects/acme.md", '---\ntitle: "Acme"\n---\n# Acme\n')
  H.write(root .. "/daily/daily-2026-10-14.md", "# day\n")
  select_picks()
  child.cmd("Logpose find topics")
  local labels = child.lua_get("_G.offered")[1].labels
  table.sort(labels)
  eq(labels, { "----------  project  Acme", "----------  topic  X" })
end

return T

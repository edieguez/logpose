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
      H.freeze(child, 2026, 10, 15) -- Thursday
    end,
    post_once = child.stop,
  },
})

local function task(name, status, extra)
  H.write(
    root .. "/tasks/" .. name .. ".md",
    ("---\ntitle: %q\nstatus: %s\n%s---\n## Context\n"):format(name, status, extra or "")
  )
end

T["menu"] = MiniTest.new_set()

T["menu"][":Logpose alone lists every command with what it does and your keymap"] = function()
  child.lua([[vim.keymap.set("n", "<Space>jd", "<Plug>(logpose-daily)")]])
  child.lua([[vim.keymap.set("n", "<Space>jt", "<cmd>Logpose find tasks open<cr>")]])
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.prompt = opts.prompt
    _G.labels = vim.tbl_map(opts.format_item, items)
    for _, it in ipairs(items) do
      if it.name == "daily" then return cb(it) end
    end
  end]])
  child.cmd("Logpose")
  eq(child.lua_get("_G.prompt"), "Logpose")
  local labels = child.lua_get("_G.labels")
  eq(#labels, #child.lua_get("require('logpose.commands').names()"))
  local daily, find
  for _, l in ipairs(labels) do
    if l:match("^daily ") then
      daily = l
    elseif l:match("^find ") then
      find = l
    end
  end
  H.contains(daily, "open the daily note")
  H.contains(daily, "<Space>jd")
  H.contains(find, "<Space>jt")
  -- choosing runs it
  child.lua("vim.wait(50, function() return false end)")
  eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "daily-2026-10-15.md")
end

T["menu"]["most used commands come first when usage stats are on"] = function()
  setup("{ telemetry = { enabled = true } }")
  child.lua([[
    local t = require('logpose.telemetry')
    for _ = 1, 3 do t.record('stats', {}, true) end
    t.record('board', { 'move' }, true)
  ]])
  local names = child.lua_get("vim.tbl_map(function(e) return e.name end, require('logpose.menu').entries())")
  eq({ names[1], names[2] }, { "stats", "board" })
end

T["statusline"] = MiniTest.new_set()

T["statusline"]["shows project, work in progress, blockers and the sprint day"] = function()
  setup(
    ("{ projects = { paths = { [%q] = 'acme' } }, period = { kind = 'sprint', sprint = { anchor = '2026-10-15', first_number = 43 } } }"):format(
      child.fn.getcwd()
    )
  )
  task("a", "in-progress", "project: acme\n")
  task("b", "in-progress", "project: acme\nblocked: waiting on ana\n")
  task("c", "in-progress", "project: thesis\n")
  task("d", "todo", "project: acme\nblocked: yes\n")
  task("e", "done", "project: acme\nblocked: old\n")
  eq(child.lua_get("require('logpose').statusline()"), "acme · 2 in progress · 2 blocked · sprint-43 1/10")
  eq(
    child.lua_get("require('logpose').statusline({ project = false, period = false, separator = ' | ' })"),
    "2 in progress | 2 blocked"
  )
end

T["statusline"]["is cached, and logpose's own changes refresh it"] = function()
  task("a", "in-progress")
  eq(child.lua_get("require('logpose').statusline({ period = false })"), "1 in progress")
  task("b", "in-progress") -- written behind logpose's back: the cached line stays for a while
  eq(child.lua_get("require('logpose').statusline({ period = false })"), "1 in progress")
  task("c", "todo")
  child.lua(("require('logpose.taskfile').set_status(%q, 'in-progress')"):format(root .. "/tasks/c.md"))
  eq(child.lua_get("require('logpose').statusline({ period = false })"), "3 in progress")
end

T["statusline"]["weeks, and nothing outside a journal"] = function()
  task("a", "in-progress")
  eq(child.lua_get("require('logpose').statusline()"), "1 in progress · week 4/5")
  child.lua("require('logpose').setup({})")
  child.lua("require('logpose.statusline').clear()")
  eq(child.lua_get("require('logpose').statusline()"), "")
end

return T

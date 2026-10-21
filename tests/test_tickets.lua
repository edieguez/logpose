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
      child.lua(
        ("require('logpose').setup({ root = %q, picker = 'select', tickets = { url = 'https://acme.atlassian.net/browse/{id}' } })"):format(
          root
        )
      )
      H.write(root .. "/INBOX.md", "# INBOX\n- [ ] fix PROJ-123 flaky test\n- [ ] see XPROJ-1234 and PROJ-12\n")
      H.write(root .. "/meetings/2026-10-14 - retro.md", "# Retro\n- discussed (PROJ-123).\n")
      child.lua([[_G.opened = {}; vim.ui.open = function(u) table.insert(_G.opened, u) end]])
    end,
    post_once = child.stop,
  },
})

T["ticket at the cursor"] = function()
  local at = function(line, col)
    return child.lua_get(("require('logpose.tickets').at(%q, %d)"):format(line, col))
  end
  eq(at("fix PROJ-123 now", 4), "PROJ-123")
  eq(at("fix PROJ-123 now", 11), "PROJ-123")
  eq(at("fix PROJ-123 now", 12), vim.NIL)
  eq(at("(PROJ-123).", 1), "PROJ-123")
  eq(at("XPROJ-1234", 3), "XPROJ-1234")
  eq(at("proj-123", 2), vim.NIL)
end

T["gx opens the ticket, or falls back"] = function()
  child.cmd("edit " .. root .. "/INBOX.md")
  child.bo.filetype = "markdown"
  child.api.nvim_win_set_cursor(0, { 2, 10 })
  child.type_keys("gx")
  eq(child.lua_get("_G.opened"), { "https://acme.atlassian.net/browse/PROJ-123" })
  child.api.nvim_buf_set_lines(0, 2, 3, false, { "https://example.com/x" })
  child.api.nvim_win_set_cursor(0, { 3, 5 })
  child.type_keys("gx")
  eq(child.lua_get("_G.opened[2]"), "https://example.com/x")
end

T["gx is only mapped in the journal"] = function()
  local outside = H.tmpdir() .. "/x.md"
  H.write(outside, "PROJ-1\n")
  child.cmd("edit " .. outside)
  child.bo.filetype = "markdown"
  eq(child.lua_get("vim.fn.maparg('gx', 'n', false, true).buffer == 1"), false)
  child.lua(("require('logpose').setup({ root = %q })"):format(root))
  child.cmd("edit " .. root .. "/INBOX.md")
  child.bo.filetype = "markdown"
  eq(child.lua_get("vim.fn.maparg('gx', 'n', false, true).buffer == 1"), true) -- for note links
end

T["gx follows note links, spaces and all, and hands the rest to your gx"] = function()
  child.lua("vim.keymap.set('n', 'gx', function() _G.mine = vim.fn.expand('<cfile>') end)") -- e.g. a markdown plugin's
  H.write(root .. "/meetings/acme/2026-10-15 - retro.md", "# Retro\n")
  local task = root .. "/tasks/fix-ci.md"
  H.write(task, table.concat({
    "From: [[meetings/acme/2026-10-15 - retro|Retro]]",
    "Also [the retro](<../meetings/acme/2026-10-15 - retro.md>) and [[2026-10-15 - retro]]",
    "Missing: [[meetings/nope]] and https://example.com/x",
  }, "\n") .. "\n")
  local function gx(row, col)
    child.cmd("edit " .. task)
    child.bo.filetype = "markdown"
    child.api.nvim_win_set_cursor(0, { row, col })
    child.type_keys("gx")
    return child.api.nvim_buf_get_name(0)
  end
  local retro = root .. "/meetings/acme/2026-10-15 - retro.md"
  eq(gx(1, 30), retro) -- on the path, past the space
  eq(gx(1, 47), retro) -- on the label
  eq(gx(2, 8), retro) -- markdown link with <spaces>
  eq(gx(2, 70), retro) -- a short wiki link
  eq(gx(3, 14), task)
  H.contains(child.notifications()[#child.notifications()].msg, "no note at [[meetings/nope]]")
  eq(gx(3, 40), task)
  eq(child.lua_get("_G.mine"), "https://example.com/x") -- yours, untouched
end

T[":Logpose ticket lists whole-word mentions"] = function()
  child.lua(
    [[vim.ui.select = function(items, opts, cb) _G.labels = vim.tbl_map(opts.format_item, items); _G.prompt = opts.prompt; cb(items[2]) end]]
  )
  child.cmd("Logpose ticket PROJ-123")
  eq(child.lua_get("_G.prompt"), "PROJ-123")
  eq(
    child.lua_get("_G.labels"),
    { "INBOX.md: - [ ] fix PROJ-123 flaky test", "meetings/2026-10-14 - retro.md: - discussed (PROJ-123)." }
  )
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
end

T[":Logpose ticket uses the ID under the cursor"] = function()
  child.lua([[vim.ui.select = function(items, opts, cb) _G.prompt = opts.prompt; cb(nil) end]])
  child.cmd("edit " .. root .. "/INBOX.md")
  child.api.nvim_win_set_cursor(0, { 3, 26 })
  child.cmd("Logpose ticket")
  eq(child.lua_get("_G.prompt"), "PROJ-12")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Logpose ticket")
  H.contains(child.notifications()[1].msg, "no ticket under the cursor")
  child.cmd("Logpose ticket NOPE-1")
  H.contains(child.notifications()[2].msg, "isn't mentioned anywhere")
end

return T

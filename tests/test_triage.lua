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
      H.write(root .. "/INBOX.md", table.concat({
        "# INBOX",
        "",
        "## 2026-10-12",
        "- [ ] old one",
        "- [ ] second",
        "",
        "## 2026-10-13",
        "- [ ] newer #acme",
        "- [x] closed",
        "",
        "## Someday",
        "- [ ] parked",
      }, "\n") .. "\n")
      H.write(
        root .. "/meetings/acme/2026-10-14 - retro.md",
        '---\ntype: retro\ndate: 2026-10-14\nproject: acme\ntitle: "Retro"\n---\n# Retro\n\n## Action items\n- [ ] existing\n\n## Notes\n'
      )
    end,
    post_once = child.stop,
  },
})

--- Answer prompts in order: selects pick the first item whose label contains the answer.
local function answers(...)
  child.lua(("_G.answers = %s"):format(vim.inspect({ ... })))
  child.lua([[
    _G.prompts = {}
    local function nexta() return table.remove(_G.answers, 1) end
    vim.ui.select = function(items, opts, cb)
      table.insert(_G.prompts, opts.prompt)
      local want = nexta()
      for _, it in ipairs(items) do
        local label = opts.format_item and opts.format_item(it) or it
        if want and label:find(want, 1, true) then return cb(it) end
      end
      cb(nil)
    end
    vim.ui.input = function(opts, cb) table.insert(_G.prompts, opts.prompt); cb(nexta()) end
  ]])
end

local function inbox()
  return H.read(root .. "/INBOX.md")
end

local function last_note()
  local n = child.notifications()
  return n[#n].msg
end

T["tag a project, move into a note, drop, quit"] = function()
  answers("project", "acme", "move", "Retro", "drop", "Drop", "quit")
  child.cmd("Logpose triage")
  local prompts = child.lua_get("_G.prompts")
  eq(prompts[1], "Triage 1/3 (2026-10-12): old one")
  eq(inbox(), table.concat({
    "# INBOX",
    "",
    "## 2026-10-12",
    "",
    "## 2026-10-13",
    "- [ ] newer #acme",
    "- [x] closed",
    "",
    "## Someday",
    "- [ ] parked",
  }, "\n") .. "\n")
  H.contains(
    H.read(root .. "/meetings/acme/2026-10-14 - retro.md"),
    "## Action items\n- [ ] existing\n- [ ] old one #acme\n\n## Notes"
  )
  H.contains(last_note(), "triage finished: 1 tagged, 1 moved, 1 dropped; 1 left in INBOX")
end

T["due with a relative date, done, someday"] = function()
  answers("due", "+3d", "done", "someday", "skip")
  child.cmd("Logpose triage")
  H.contains(H.read(root .. "/DONE.md"), "## 2026-10-14\n- [x] old one due:2026-10-17\n")
  H.contains(inbox(), "## Someday\n- [ ] parked\n- [ ] second\n")
  eq(inbox():find("old one", 1, true), nil)
  H.contains(last_note(), "1 tagged, 1 done, 1 someday, 1 skipped; 1 left")
end

T["tags and owner stay on the same item"] = function()
  answers("tag", "perf #ux", "owner", "ana", "due", "soon", "quit")
  child.cmd("Logpose triage")
  H.contains(inbox(), "- [ ] old one #perf #ux @ana\n")
  H.contains(child.notifications()[1].msg, 'not a date: "soon"')
  eq(#child.lua_get("_G.prompts"), 7)
end

T["filters limit the queue"] = function()
  answers("quit")
  child.cmd("Logpose triage #acme")
  eq(child.lua_get("_G.prompts")[1], "Triage 1/1 (2026-10-13): newer #acme")
end

T["drop asks once per session"] = function()
  child.lua("require('logpose.triage')._drop_confirmed = false")
  answers("drop", "Drop", "drop", "quit")
  child.cmd("Logpose triage")
  local drops = vim.tbl_filter(function(p)
    return p:find("Delete this item", 1, true) ~= nil
  end, child.lua_get("_G.prompts"))
  eq(#drops, 1)
  eq(inbox():find("old one", 1, true), nil)
  eq(inbox():find("second", 1, true), nil)
end

T["edits an open INBOX buffer, undoably"] = function()
  child.cmd("edit " .. root .. "/INBOX.md")
  answers("done", "quit")
  child.cmd("Logpose triage")
  eq(inbox():find("old one", 1, true), nil) -- saved
  child.cmd("undo")
  eq(child.api.nvim_buf_get_lines(0, 3, 4, false), { "- [ ] old one" })
end

T["cancelling the menu ends the session"] = function()
  answers()
  child.cmd("Logpose triage")
  H.contains(last_note(), "triage finished; 3 left in INBOX")
end

T["an empty INBOX says so"] = function()
  H.write(root .. "/INBOX.md", "# INBOX\n- [x] all done\n")
  child.cmd("Logpose triage")
  H.contains(last_note(), "INBOX is clear")
end

return T

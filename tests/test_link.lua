local H = dofile("tests/helpers.lua")
local link = require("logpose.link")
local eq = H.eq

local T = MiniTest.new_set()

local root = "/home/me/journal-repo"
local daily = root .. "/journal/daily/daily-2026-10-14.md"
local meeting = root .. "/journal/meetings/2026-10-14 - retro.md"

T["relpath"] = function()
  eq(link.relpath("/a/b/c", "/a/b/c/d.md"), "d.md")
  eq(link.relpath("/a/b/c", "/a/x/y.md"), "../../x/y.md")
  eq(link.relpath("/a", "/a"), ".")
end

T["wiki links are relative to link_base, without .md"] = function()
  eq(link.make(daily, meeting, "Retro", root, "wiki"), "[[meetings/2026-10-14 - retro|Retro]]")
  eq(link.make(daily, meeting, "", root, "wiki"), "[[meetings/2026-10-14 - retro]]")
end

T["markdown links are relative to the source file"] = function()
  eq(link.make(daily, meeting, "Retro", root, "markdown"), "[Retro](<../meetings/2026-10-14 - retro.md>)")
  eq(link.make(daily, root .. "/journal/daily/x.md", "X", root, "markdown"), "[X](x.md)")
end

return T

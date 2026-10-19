local H = dofile("tests/helpers.lua")
local markdown = require("logpose.markdown")
local eq = H.eq

local T = MiniTest.new_set()

T["heading_date accepts trailing spaces only"] = function()
  eq(markdown.heading_date("## 2026-10-05  "), "2026-10-05")
  eq(markdown.heading_date("## 2026-10-05 notes"), nil)
  eq(markdown.heading_date("# 2026-10-05"), nil)
end

T["trim_blank"] = function()
  eq(markdown.trim_blank({ "", " ", "a", "", "b", "", "" }), { "a", "", "b" })
  eq(markdown.trim_blank({ "", "a", "" }, false, true), { "", "a" })
  eq(markdown.trim_blank({ "", "" }), {})
end

return T

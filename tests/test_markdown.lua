local H = dofile("tests/helpers.lua")
local markdown = require("logpose.markdown")
local eq = H.eq

local T = MiniTest.new_set()

T["parse -> render is lossless"] = function()
  for _, s in ipairs({
    "",
    "\n",
    "no newline",
    "# INBOX\n",
    "# INBOX\n\n## 2026-10-05\n- [ ] a\n\n## Someday\nidea\n\n## 2026-10-07\n- [ ] b\n",
    "## 2026-10-05\n- x",
    "# T\n\n\n## 2026-10-05\n\n\n- x\n\n\n",
    "### 2026-10-05\n#2026\n##no space\n",
  }) do
    eq(markdown.render(markdown.parse(s)), s)
  end
end

T["parse classifies blocks"] = function()
  local doc = markdown.parse("# T\n\n## 2026-10-05\n- a\n## Someday\n## 2026-13-01\n### 2026-10-06\n")
  local kinds = vim.tbl_map(function(b)
    return { b.kind, b.date }
  end, doc.blocks)
  eq(kinds, { { "preamble" }, { "date", "2026-10-05" }, { "other" }, { "other" } })
  eq(doc.blocks[4].lines, { "## 2026-13-01", "### 2026-10-06" })
end

T["heading_date accepts trailing spaces only"] = function()
  eq(markdown.heading_date("## 2026-10-05  "), "2026-10-05")
  eq(markdown.heading_date("## 2026-10-05 notes"), nil)
  eq(markdown.heading_date("# 2026-10-05"), nil)
end

T["detect_order"] = function()
  eq(markdown.detect_order(markdown.parse("## 2026-10-07\n## 2026-10-05\n")), "newest_first")
  eq(markdown.detect_order(markdown.parse("## 2026-10-05\n## 2026-10-05\n## 2026-10-07\n")), "oldest_first")
  eq(markdown.detect_order(markdown.parse("## 2026-10-05\n")), nil)
end

T["trim_blank"] = function()
  eq(markdown.trim_blank({ "", " ", "a", "", "b", "", "" }), { "a", "", "b" })
  eq(markdown.trim_blank({ "", "a", "" }, false, true), { "", "a" })
  eq(markdown.trim_blank({ "", "" }), {})
end

return T

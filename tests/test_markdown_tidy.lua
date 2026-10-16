local H = dofile("tests/helpers.lua")
local eq = H.eq
local markdown = require("logpose.markdown")

local T = MiniTest.new_set()

local function tidy(...)
  return markdown.tidy({ ... })
end

T["blank lines around headings, lists, tables and fences"] = function()
  eq(
    tidy(
      "# Title",
      "text",
      "## Section",
      "- a",
      "- b",
      "after",
      "| x |",
      "|---|",
      "para",
      "```lua",
      "",
      "",
      "x",
      "```",
      "end"
    ),
    {
      "# Title",
      "",
      "text",
      "",
      "## Section",
      "",
      "- a",
      "- b",
      "after", -- a lazy continuation line belongs to the list
      "",
      "| x |",
      "|---|",
      "",
      "para",
      "",
      "```lua",
      "",
      "",
      "x", -- code is left alone
      "```",
      "",
      "end",
    }
  )
end

T["runs of blank lines collapse; trailing ones go; frontmatter is kept"] = function()
  eq(tidy("---", "title: x", "", "---", "", "", "## A", "", "", "", "text", "", ""), {
    "---",
    "title: x",
    "",
    "---",
    "## A",
    "",
    "text",
  })
end

T["trailing spaces go, a two-space hard break stays"] = function()
  eq(tidy("one ", "two  ", "three   ", "   "), { "one", "two  ", "three" })
end

T["follows a row through the rewrite"] = function()
  local out, row = markdown.tidy({ "## A", "", "", "", "## B" }, 3)
  eq(out, { "## A", "", "## B" })
  eq(row, 2)
  local _, r2 = markdown.tidy({ "---", "t: x", "---", "" }, 4)
  eq(r2, 4) -- an empty body keeps one line for the cursor
end

T["wrap breaks long list items outside links"] = function()
  local line = "- [ ] follow up with the platform team @ana due:2026-10-20 ([[meetings/acme/2026-10-07 - retro|Retro]])"
  eq(markdown.wrap(line, 80), {
    "- [ ] follow up with the platform team @ana due:2026-10-20",
    "  ([[meetings/acme/2026-10-07 - retro|Retro]])",
  })
  eq(markdown.wrap("- short", 80), { "- short" })
  eq(markdown.wrap("not a list item " .. string.rep("x ", 50), 80)[2], nil)
end

return T

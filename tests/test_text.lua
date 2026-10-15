local H = dofile("tests/helpers.lua")
local text = require("logpose.util.text")
local eq = H.eq

local T = MiniTest.new_set()

T["trim"] = function()
  eq(text.trim("  hola  "), "hola")
  eq(text.trim("\t\n"), "")
  eq(text.trim("a b"), "a b")
end

T["slugify"] = MiniTest.new_set()

T["slugify"]["transliterates Spanish accents"] = function()
  eq(text.slugify("Reunión de planeación"), "reunion-de-planeacion")
  eq(text.slugify("Año nuevo, pingüino"), "ano-nuevo-pinguino")
  eq(text.slugify("ÁÉÍÓÚ Ñ Ü"), "aeiou-n-u")
end

T["slugify"]["collapses punctuation and other symbols"] = function()
  eq(text.slugify("  Sprint 42 — Retro!! "), "sprint-42-retro")
  eq(text.slugify("1:1 with Ana"), "1-1-with-ana")
  eq(text.slugify("PROJ-123 / hotfix"), "proj-123-hotfix")
end

T["slugify"]["returns empty for symbol-only titles"] = function()
  eq(text.slugify("¿?"), "")
  eq(text.slugify("---"), "")
  eq(text.slugify(""), "")
end

T["slugify"]["lowercases ASCII and collapses separators"] = function()
  eq(text.slugify("Sprint Planning"), "sprint-planning")
  eq(text.slugify("Q4 roadmap: review & sync"), "q4-roadmap-review-sync")
end

return T

--- Text helpers.
local M = {}

-- Latin accented letters -> ASCII. Keys are UTF-8 byte sequences.
local TRANSLIT = {}
do
  local groups = {
    a = "áàäâãå",
    e = "éèëê",
    i = "íìïî",
    o = "óòöôõ",
    u = "úùüû",
    n = "ñ",
    c = "ç",
    A = "ÁÀÄÂÃÅ",
    E = "ÉÈËÊ",
    I = "ÍÌÏÎ",
    O = "ÓÒÖÔÕ",
    U = "ÚÙÜÛ",
    N = "Ñ",
    C = "Ç",
  }
  for ascii, chars in pairs(groups) do
    for ch in chars:gmatch("[\192-\244][\128-\191]*") do
      TRANSLIT[ch] = ascii
    end
  end
end

---@param s string
---@return string
function M.trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

--- Replace accented Latin letters with ASCII; other non-ASCII characters become spaces.
---@param s string
---@return string
function M.transliterate(s)
  return (s:gsub("[\192-\244][\128-\191]*", function(ch)
    return TRANSLIT[ch] or " "
  end))
end

--- Filename-safe slug: `"Reunión de planeación"` -> `"reunion-de-planeacion"`.
--- May return `""`; callers supply a fallback.
---@param s string
---@return string
function M.slugify(s)
  local slug = M.transliterate(s):lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return slug
end

return M

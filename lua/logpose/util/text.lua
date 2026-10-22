--- Text helpers.
local M = {}

-- What #tags and @mentions are made of: letters, digits, `_` and any non-ASCII byte, so
-- accented words (`#reunión`, `@José`) count whole. Patterns for `gmatch`/`gsub`.
local W = "%w_\128-\255"
M.TAG = "[" .. W .. "][" .. W .. "%-/]*"
M.HANDLE = "[" .. W .. "][" .. W .. "%.%-]*"
M.TAG_CHARS = "[" .. W .. "%-/]"
M.HANDLE_CHARS = "[" .. W .. "%.%-]"

-- Latin accented letters -> ASCII. Keys are UTF-8 byte sequences.
local TRANSLIT = {}
do
  local groups = {
    a = "áàäâãå",
    e = "éèëê",
    i = "íìïî",
    o = "óòöôõø",
    u = "úùüû",
    n = "ñ",
    c = "ç",
    y = "ýÿ",
    A = "ÁÀÄÂÃÅ",
    E = "ÉÈËÊ",
    I = "ÍÌÏÎ",
    O = "ÓÒÖÔÕØ",
    U = "ÚÙÜÛ",
    N = "Ñ",
    C = "Ç",
    Y = "Ý",
  }
  for ascii, chars in pairs(groups) do
    for ch in chars:gmatch("[\192-\244][\128-\191]*") do
      TRANSLIT[ch] = ascii
    end
  end
end

--- Lowercase, without accents: what matching compares. Other non-ASCII stays as it is.
---@param s string
---@return string
function M.plain(s)
  return (s:gsub("[\192-\244][\128-\191]*", TRANSLIT):lower())
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

--- `s` when it's a non-empty string, else nil (form and frontmatter values).
---@param s any
---@return string?
function M.nonempty(s)
  return type(s) == "string" and s ~= "" and s or nil
end

--- Filename-safe slug: `"Reunión de planeación"` -> `"reunion-de-planeacion"`.
--- May return `""`; callers supply a fallback.
---@param s string
---@return string
function M.slugify(s)
  local slug = M.transliterate(s):lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return slug
end

--- Substitute `{name}` variables. Unknown variables are left as they are.
--- Uses a function replacement, so `%` in values is safe.
---@param s string
---@param vars table<string, any>
---@return string
function M.substitute(s, vars)
  return (
    s:gsub("{([%w_]+)}", function(key)
      local v = vars[key]
      if v == nil then
        return nil -- keep the original text
      end
      return tostring(v)
    end)
  )
end

return M

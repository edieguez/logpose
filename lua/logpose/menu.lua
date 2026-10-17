--- `:Logpose` with no subcommand: every command in a picker, with what it does and your keymap
--- for it. Commands you use most come first (when usage stats are on).
local M = {}

--- Your normal/visual-mode mappings that run each command: `<Plug>(logpose-x)` or `:Logpose x…`.
---@return table<string, string> name -> lhs as typed (e.g. "<Space>jd")
function M.keymaps()
  local out = {}
  for _, mode in ipairs({ "n", "x" }) do
    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
      local rhs = map.rhs or ""
      local name = rhs:match("^<Plug>%(logpose%-([%w%-]+)%)$") or rhs:match("Logpose!?%s+([%w%-]+)")
      if name and not map.lhs:match("^<Plug>") and not out[name] then
        out[name] = vim.fn.keytrans(map.lhs)
      end
    end
  end
  return out
end

--- Uses per command over the last 30 days (empty when usage stats are off).
---@return table<string, integer>
local function usage()
  local ok, counts = pcall(function()
    return require("logpose.telemetry").totals(30)
  end)
  local out = {}
  for key, n in pairs(ok and counts or {}) do
    local name = key:match("^(%S+)")
    out[name] = (out[name] or 0) + n
  end
  return out
end

--- Menu entries, most used first, then alphabetical.
---@return { display: string, name: string }[]
function M.entries()
  local commands = require("logpose.commands")
  local keys, used = M.keymaps(), usage()
  local names = commands.names()
  table.sort(names, function(a, b)
    local ua, ub = used[a] or 0, used[b] or 0
    if ua ~= ub then
      return ua > ub
    end
    return a < b
  end)
  local width = 0
  for _, name in ipairs(names) do
    width = math.max(width, #name)
  end
  return vim.tbl_map(function(name)
    local desc = (commands.subcommands[name].desc or ""):gsub("^logpose:%s*", "")
    local key = keys[name] and ("  " .. keys[name]) or ""
    return { display = ("%-" .. width .. "s  %s%s"):format(name, desc, key), name = name }
  end, names)
end

function M.open()
  require("logpose.picker").pick(M.entries(), {
    prompt = "Logpose",
    on_choice = function(choice)
      vim.schedule(function()
        vim.cmd("Logpose " .. choice.name)
      end)
    end,
  })
end

return M

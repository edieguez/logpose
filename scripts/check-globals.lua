-- Fails if any Lua file assigns a global variable (a missing `local`, or a local declared after
-- the function that uses it). Usage: nvim -l scripts/check-globals.lua FILE...
local bc = require("jit.bc")
local found = 0
for _, f in ipairs(_G.arg) do
  local fn = assert(loadfile(f))
  local out = {}
  local sink = {
    write = function(_, s)
      table.insert(out, s)
    end,
    flush = function() end,
    close = function() end,
  }
  bc.dump(fn, sink, true)
  for line in table.concat(out):gmatch("[^\n]+") do
    local name = line:match('GSET.-;%s+"([^"]+)"')
    if name then
      io.stderr:write(("%s: assigns the global %q\n"):format(f, name))
      found = found + 1
    end
  end
end
if found > 0 then
  os.exit(1)
end

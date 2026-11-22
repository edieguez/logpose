-- The sample configs in examples/ stay in step with the defaults: a new option, a changed default or a
-- renamed one fails here until the samples follow.
local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = { pre_case = child.setup, post_once = child.stop },
})

-- In the child: load a sample spec (with `examples`, its commented-out options and spec fields turned on),
-- give its opts to setup() and say how that went.
local CHECK = [[
_G.check = function(file, examples)
  local lines = vim.fn.readfile(file)
  if examples then
    for i, l in ipairs(lines) do
      -- `-- key = value,` (a comment may follow): an example, not a sentence of a comment
      local indent, body = l:match("^(%s*)%-%- (.*)$")
      local key = body and body:match("^(.-) = ")
      local is_key = key and (key:match("^[%a_][%w_]*$") or key:match('^%["[^"]+"%]$'))
      if is_key and (body:match(",%s*$") or body:match(",%s+%-%- ")) then
        lines[i] = indent .. body
      end
    end
  end
  local spec = assert(load(table.concat(lines, "\n"), "@" .. file))()
  _G.notifications = {}
  local config = require("logpose.config")
  local ok, err = pcall(config.setup, vim.deepcopy(spec.opts))
  -- the options the sample leaves out
  local missing = {}
  local function walk(defaults, opts, path)
    for k, v in pairs(defaults) do
      local p = path == "" and k or (path .. "." .. k)
      if opts[k] == nil then
        table.insert(missing, p)
      elseif type(v) == "table" and not vim.islist(v) and next(v) and not config.open_keys[p] then
        walk(v, opts[k], p)
      end
    end
  end
  walk(config.defaults, spec.opts, "")
  local optional = vim.tbl_keys(config.optional_keys) -- options without a default
  for _, p in ipairs(optional) do
    local v = spec.opts
    for part in p:gmatch("[^.]+") do
      v = type(v) == "table" and v[part] or nil
    end
    if v == nil then
      table.insert(missing, p)
    end
  end
  table.sort(missing)
  table.sort(optional)
  return {
    plugin = spec[1],
    ok = ok,
    err = not ok and tostring(err) or nil,
    warnings = vim.tbl_map(function(n) return n.msg end, _G.notifications),
    defaults = ok and vim.deep_equal(config.options, config.defaults),
    missing = missing,
    optional = optional,
    sets = next(spec.opts) ~= nil,
  }
end
]]

local function check(name, examples)
  child.lua(CHECK)
  local file = vim.fs.joinpath(vim.fn.getcwd(), "examples", name)
  return child.lua_get(("_G.check(%q, %s)"):format(file, tostring(examples or false)))
end

T["examples/logpose.lua sets every option to its default"] = function()
  local r = check("logpose.lua")
  eq(r.err, nil)
  eq(r.warnings, {})
  eq(r.plugin, "edieguez/logpose")
  eq(r.defaults, true)
  -- all it leaves out are the options without a default, which it has commented examples of
  eq(r.missing, r.optional)
end

T["examples/logpose.lua: its commented examples are valid options, for every one without a default"] = function()
  local r = check("logpose.lua", true)
  eq(r.err, nil)
  eq(r.warnings, {})
  eq(r.missing, {})
end

T["examples/logpose.local.lua: the same plugin, nothing set until you uncomment it, valid examples"] = function()
  local r = check("logpose.local.lua")
  eq({ r.plugin, r.ok, r.sets }, { "edieguez/logpose", true, false })
  r = check("logpose.local.lua", true)
  eq(r.err, nil)
  eq(r.warnings, {})
  eq(r.sets, true)
end

return T

local H = {}

H.eq = MiniTest.expect.equality
H.neq = MiniTest.expect.no_equality

--- Child Neovim with the plugin loaded via tests/minimal_init.lua.
function H.new_child()
  local child = MiniTest.new_child_neovim()
  function child.setup()
    -- Fresh data dir per case so saved state (stdpath("data")) never leaks or touches the real one.
    vim.env.XDG_DATA_HOME = H.tmpdir()
    child.restart({ "-u", "tests/minimal_init.lua" })
    -- Capture notifications instead of printing them.
    child.lua([[
      _G.notifications = {}
      vim.notify = function(msg, level) table.insert(_G.notifications, { msg = msg, level = level }) end
      -- An unstubbed prompt would block the headless child forever: fail fast instead.
      vim.ui.select = function(_, opts) error("unexpected vim.ui.select: " .. tostring(opts and opts.prompt)) end
      vim.ui.input = function(opts) error("unexpected vim.ui.input: " .. tostring(opts and opts.prompt)) end
    ]])
  end
  function child.notifications()
    return child.lua_get("_G.notifications")
  end
  return child
end

--- Fresh temp directory (realpath, so it compares equal to what Neovim reports on macOS).
function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return (vim.uv or vim.loop).fs_realpath(dir)
end

function H.write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

function H.read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

--- Freeze the child's clock (local time).
function H.freeze(child, y, m, d, hour, min)
  child.lua(
    ("require('logpose.util.date')._now = function() return os.time({ year = %d, month = %d, day = %d, hour = %d, min = %d }) end"):format(
      y,
      m,
      d,
      hour or 10,
      min or 30
    )
  )
end

--- Journal root fixture: a temp dir with the default marker.
function H.journal()
  local root = H.tmpdir()
  H.write(root .. "/.logpose", "")
  return root
end

--- Assert that `s` contains `needle` (plain match).
function H.contains(s, needle)
  if not tostring(s):find(needle, 1, true) then
    error(("expected to find %q in:\n%s"):format(needle, tostring(s)), 2)
  end
end

return H

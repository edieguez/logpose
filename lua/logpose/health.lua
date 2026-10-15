--- :checkhealth logpose
local M = {}

function M.check()
  local h = vim.health
  local config = require("logpose.config")
  local fs = require("logpose.util.fs")

  h.start("logpose: environment")
  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. version)
  else
    h.error("Neovim " .. version .. " is too old; logpose needs 0.10+")
  end
  if config.options then
    h.ok("setup() has been called")
  else
    h.info("setup() not called; using defaults")
  end

  h.start("logpose: journal root")
  local root, source = config.resolve_root()
  if not root then
    h.error(source, {
      'Set it explicitly: require("logpose").setup({ root = "~/path/to/journal" })',
      "Or add one of these markers to the journal root: " .. table.concat(config.get().root_markers, ", "),
    })
    return
  end
  local how = ({
    config = "from setup({ root = ... })",
    buffer = "found by marker above the current buffer",
    cwd = "found by marker above the current directory",
  })[source] or source
  h.ok(("%s (%s)"):format(vim.fn.fnamemodify(root, ":~"), how))
  if source ~= "config" then
    h.info("Setting `root` explicitly makes commands work from any buffer, e.g. a work repo.")
  end

  h.start("logpose: journal paths")
  local keys = vim.tbl_keys(config.get().dirs)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local path = config.path(key, root)
    local rel = config.get().dirs[key]
    if fs.exists(path) then
      h.ok(("%s: %s"):format(key, rel))
    else
      h.warn(("%s: %s does not exist yet (created on first use)"):format(key, rel))
    end
  end

  h.start("logpose: picker")
  local backend, warning = require("logpose.picker").detect(config.get().picker)
  if warning then
    h.warn(warning)
  end
  if backend == "select" then
    h.info("No picker plugin found; using vim.ui.select (snacks.nvim, fzf-lua or telescope recommended)")
  else
    h.ok("Using " .. backend)
  end
end

return M

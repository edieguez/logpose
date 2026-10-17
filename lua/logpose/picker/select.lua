--- vim.ui.select fallback backend.
local ui = require("logpose.util.ui")

local M = {}

function M.pick(items, opts)
  vim.ui.select(
    items,
    {
      prompt = opts.prompt,
      format_item = function(it)
        return it.display
      end,
    },
    ui.safely(function(choice)
      if choice then
        opts.on_choice(choice)
      end
    end)
  )
end

--- No live grep without a picker plugin: search once and fill the quickfix list.
local function vimgrep(cwd, text)
  local pattern = "\\V" .. text:gsub("\\", "\\\\"):gsub("/", "\\/")
  local files = vim.fn.fnameescape(cwd) .. "/**/*.md"
  local ok = pcall(vim.cmd, ("silent vimgrep /%s/jg %s"):format(pattern, files))
  if not ok or #vim.fn.getqflist() == 0 then
    require("logpose.util.ui").notify(("logpose: no matches for %q"):format(text), vim.log.levels.INFO)
    return
  end
  vim.cmd("copen")
end

function M.grep(opts)
  if opts.text and opts.text ~= "" then
    vimgrep(opts.cwd, opts.text)
    return
  end
  vim.ui.input(
    { prompt = "Grep journal: " },
    ui.safely(function(input)
      if input and input ~= "" then
        vimgrep(opts.cwd, input)
      end
    end)
  )
end

return M

--- fzf-lua backend.
local M = {}

function M.pick(items, opts)
  local fzf = require("fzf-lua")
  local by_entry, entries, has_files = {}, {}, false
  for i, it in ipairs(items) do
    local entry
    if it.file then
      has_files = true
      -- "file:line: text" lets fzf-lua's builtin previewer show the file at that line.
      local path = opts.cwd and require("logpose.link").relpath(opts.cwd, it.file)
        or vim.fn.fnamemodify(it.file, ":~:.")
      entry = ("%s:%d: %s"):format(path, it.lnum or 1, it.display)
    else
      entry = it.display
    end
    if by_entry[entry] then
      entry = ("%s [%d]"):format(entry, i) -- keep entries unique
    end
    by_entry[entry] = it
    entries[i] = entry
  end
  fzf.fzf_exec(entries, {
    prompt = opts.prompt .. "> ",
    cwd = opts.cwd,
    previewer = has_files and "builtin" or nil,
    fzf_opts = { ["--no-sort"] = true },
    actions = {
      ["default"] = function(selected)
        local it = selected and by_entry[selected[1]]
        if it then
          opts.on_choice(it)
        end
      end,
    },
  })
end

function M.grep(opts)
  require("fzf-lua").live_grep({ cwd = opts.cwd, search = opts.text })
end

return M

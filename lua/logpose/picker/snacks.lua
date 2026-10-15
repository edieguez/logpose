--- snacks.picker backend.
local M = {}

function M.pick(items, opts)
  local has_files = false
  local entries = {}
  for i, it in ipairs(items) do
    has_files = has_files or it.file ~= nil
    entries[i] = {
      idx = i,
      text = it.display,
      file = it.file,
      pos = it.file and { it.lnum or 1, 0 } or nil,
      value = it,
    }
  end
  require("snacks").picker.pick({
    title = opts.prompt,
    items = entries,
    format = "text",
    preview = has_files and "file" or "none",
    layout = not has_files and { preset = "select" } or nil,
    sort = { fields = { "score:desc", "idx" } }, -- keep logpose's order when the query is empty
    confirm = function(picker, item)
      picker:close()
      if item then
        opts.on_choice(item.value)
      end
    end,
  })
end

function M.grep(opts)
  require("snacks").picker.grep({ cwd = opts.cwd, dirs = { opts.cwd }, search = opts.text })
end

return M

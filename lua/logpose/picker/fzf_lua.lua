--- fzf-lua backend.
local M = {}

--- fzf lines for `items`, filling `by_entry` (line -> item).
---@param items logpose.PickItem[]
---@param opts logpose.PickOpts
---@param by_entry table<string, logpose.PickItem>
---@return string[] entries, boolean has_files, boolean has_text
local function entries(items, opts, by_entry)
  local out, has_files, has_text = {}, false, false
  for i, it in ipairs(items) do
    local entry
    if it.file then
      has_files = true
      -- "file:line: text" lets fzf-lua's builtin previewer show the file at that line.
      local path = opts.cwd and require("logpose.link").relpath(opts.cwd, it.file)
        or vim.fn.fnamemodify(it.file, ":~:.")
      entry = ("%s:%d: %s"):format(path, it.lnum or 1, it.display)
    else
      has_text = has_text or it.preview ~= nil
      entry = it.display
    end
    if by_entry[entry] then
      entry = ("%s [%d]"):format(entry, i) -- keep entries unique
    end
    by_entry[entry] = it
    out[i] = entry
  end
  return out, has_files, has_text
end

---@param opts logpose.PickOpts
---@param by_entry fun(): table<string, logpose.PickItem>
local function actions(opts, by_entry)
  return {
    ["default"] = function(selected)
      local it = selected and by_entry()[selected[1]]
      if it then
        opts.on_choice(it)
      end
    end,
  }
end

function M.pick(items, opts)
  local by_entry = {}
  local list, has_files, has_text = entries(items, opts, by_entry)
  local preview
  if has_text and not has_files then
    preview = function(selected)
      local it = selected and by_entry[selected[1]]
      return it and it.preview or ""
    end
  end
  require("fzf-lua").fzf_exec(list, {
    prompt = opts.prompt .. "> ",
    cwd = opts.cwd,
    previewer = has_files and "builtin" or nil,
    preview = preview,
    fzf_opts = { ["--no-sort"] = true },
    actions = actions(opts, function()
      return by_entry
    end),
  })
end

--- fzf only displays: each keystroke reloads the list from `opts.items(query)`.
function M.live(opts)
  local by_entry = {}
  require("fzf-lua").fzf_live(function(args)
    by_entry = {}
    return (entries(opts.items(args[1] or ""), opts, by_entry))
  end, {
    prompt = opts.prompt .. "> ",
    query = opts.query,
    cwd = opts.cwd,
    previewer = "builtin",
    exec_empty_query = true,
    actions = actions(opts, function()
      return by_entry
    end),
  })
end

function M.grep(opts)
  require("fzf-lua").live_grep({ cwd = opts.cwd, search = opts.text })
end

return M

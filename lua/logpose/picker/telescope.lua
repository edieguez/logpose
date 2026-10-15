--- Telescope backend.
local M = {}

local function entry_maker(it)
  return {
    value = it,
    display = it.display,
    ordinal = it.display,
    filename = it.file,
    lnum = it.lnum,
  }
end

--- grep previewer for file items; logpose's preview text otherwise.
---@param has_files boolean
---@param has_text boolean
local function previewer(has_files, has_text)
  local conf = require("telescope.config").values
  if has_files then
    return conf.grep_previewer({})
  end
  if has_text then
    return require("telescope.previewers").new_buffer_previewer({
      title = "Preview",
      define_preview = function(self, entry)
        local text = entry.value.preview or ""
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(text, "\n"))
        vim.bo[self.state.bufnr].filetype = "markdown"
      end,
    })
  end
end

---@param opts logpose.PickOpts
local function attach(opts)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  return function(prompt_bufnr)
    actions.select_default:replace(function()
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if entry then
        opts.on_choice(entry.value)
      end
    end)
    return true
  end
end

function M.pick(items, opts)
  local has_files, has_text = false, false
  for _, it in ipairs(items) do
    has_files = has_files or it.file ~= nil
    has_text = has_text or it.preview ~= nil
  end
  require("telescope.pickers")
    .new({}, {
      prompt_title = opts.prompt,
      finder = require("telescope.finders").new_table({ results = items, entry_maker = entry_maker }),
      sorter = require("telescope.config").values.generic_sorter({}),
      previewer = previewer(has_files, has_text),
      attach_mappings = attach(opts),
    })
    :find()
end

--- The prompt is logpose's query; results keep logpose's order (no fuzzy sorting).
function M.live(opts)
  require("telescope.pickers")
    .new({}, {
      prompt_title = opts.prompt,
      default_text = opts.query,
      finder = require("telescope.finders").new_dynamic({
        fn = function(prompt)
          return opts.items(prompt or "")
        end,
        entry_maker = entry_maker,
      }),
      sorter = require("telescope.sorters").empty(),
      previewer = previewer(true, false),
      attach_mappings = attach(opts),
    })
    :find()
end

function M.grep(opts)
  require("telescope.builtin").live_grep({ cwd = opts.cwd, default_text = opts.text })
end

return M

--- Telescope backend.
local M = {}

function M.pick(items, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local has_files = false
  for _, it in ipairs(items) do
    has_files = has_files or it.file ~= nil
  end
  pickers
    .new({}, {
      prompt_title = opts.prompt,
      finder = finders.new_table({
        results = items,
        entry_maker = function(it)
          return {
            value = it,
            display = it.display,
            ordinal = it.display,
            filename = it.file,
            lnum = it.lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = has_files and conf.grep_previewer({}) or nil,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            opts.on_choice(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

function M.grep(opts)
  require("telescope.builtin").live_grep({ cwd = opts.cwd, default_text = opts.text })
end

return M

--- Evergreen notes: `:Logpose note [title]` and `:Logpose project-page [name]`.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local template = require("logpose.template")
local text = require("logpose.util.text")
local ui = require("logpose.util.ui")

local M = {}

---@param s string
local function yaml_string(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

---@param path string
---@param cursor? integer[]
local function open(path, cursor)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if cursor then
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
end

--- Create (if needed) and open a note from `tpl` with frontmatter `fm` (ordered pairs).
---@param path string
---@param tpl string template name
---@param vars table
---@param fm string[][]
---@param root string
---@param no_open? boolean only create it
---@return string path
local function create(path, tpl, vars, fm, root, no_open)
  if fs.exists(path) then
    if not no_open then
      open(path)
    end
    return path
  end
  local rendered = template.render(template.load(tpl, root), template.vars(date.today(), vars))
  local lines = { "---" }
  for _, kv in ipairs(fm) do
    table.insert(lines, kv[1] .. ": " .. kv[2])
  end
  vim.list_extend(lines, require("logpose.timestamps").lines())
  table.insert(lines, "---")
  local text, cursor = require("logpose.markdown").tidy_text(
    table.concat(lines, "\n") .. "\n" .. rendered.text,
    { rendered.cursor[1] + #lines, rendered.cursor[2] }
  )
  local ok, err = fs.write_file(path, text)
  if not ok then
    error(err, 0)
  end
  require("logpose.index").clear_cache()
  if not no_open then
    open(path, cursor)
  end
  return path
end

--- Topic note `notes/<slug>.md`.
---@param root string
---@param title string
function M.note(root, title)
  local slug = text.slugify(title)
  if slug == "" then
    error(("logpose: can't make a filename from %q"):format(title), 0)
  end
  local project = require("logpose.project").resolve(root)
  local fm = { { "title", yaml_string(title) } }
  if project then
    table.insert(fm, { "project", project })
  end
  table.insert(fm, { "tags", "[]" })
  create(
    fs.join(config.path("notes", root), slug .. ".md"),
    "note",
    { title = title, project = project or "" },
    fm,
    root
  )
end

--- Project page `projects/<slug>.md`, created if needed and opened (unless `opts.open == false`).
---@param root string
---@param name string
---@param opts? { open?: boolean }
---@return string path
function M.project_page(root, name, opts)
  local slug = require("logpose.project").normalize(name)
  if not slug then
    error(("logpose: invalid project name %q"):format(name), 0)
  end
  local fm = { { "title", yaml_string(name) }, { "type", "project" }, { "project", slug }, { "tags", "[]" } }
  return create(
    fs.join(config.path("projects", root), slug .. ".md"),
    "project",
    { title = name, project = slug },
    fm,
    root,
    opts and opts.open == false
  )
end

---@param opts logpose.CommandOpts
function M.note_command(opts)
  local title = vim.trim(table.concat(opts.args, " "))
  config.with_root(ui.safely(function(root)
    if title ~= "" then
      return M.note(root, title)
    end
    vim.ui.input(
      { prompt = "Note title: " },
      ui.safely(function(input)
        input = input and vim.trim(input) or ""
        if input == "" then
          require("logpose.util.ui").notify("logpose: cancelled (empty input)", vim.log.levels.INFO)
          return
        end
        M.note(root, input)
      end)
    )
  end))
end

---@param opts logpose.CommandOpts
function M.project_page_command(opts)
  local name = vim.trim(table.concat(opts.args, " "))
  config.with_root(ui.safely(function(root)
    if name == "" then
      name = require("logpose.project").resolve(root) or ""
    end
    if name ~= "" then
      return M.project_page(root, name)
    end
    local known = require("logpose.search").projects(root, require("logpose.index").build(root))
    if #known == 0 then
      vim.ui.input(
        { prompt = "Project: " },
        ui.safely(function(input)
          if input and vim.trim(input) ~= "" then
            M.project_page(root, vim.trim(input))
          end
        end)
      )
      return
    end
    vim.ui.select(
      known,
      { prompt = "Project page" },
      ui.safely(function(choice)
        if choice then
          M.project_page(root, choice)
        end
      end)
    )
  end))
end

function M.complete_projects(_, args)
  if #args > 0 then
    return {}
  end
  local root = config.resolve_root()
  return root and require("logpose.search").projects(root, require("logpose.index").build(root)) or {}
end

return M

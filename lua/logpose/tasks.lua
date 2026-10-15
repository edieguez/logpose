--- Kanban flow: `:Logpose capture [text]` and `:Logpose done` (current line or visual range).
local archive = require("logpose.archive")
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local link = require("logpose.link")
local markdown = require("logpose.markdown")
local ui = require("logpose.util.ui")

local M = {}

--- Parse a markdown task line.
---@param line string
---@return { indent: string, checked: boolean, text: string }?
function M.parse_task(line)
  local indent, mark, rest = line:match("^(%s*)[-*+]%s+%[([ xX])%]%s?(.*)$")
  if not indent then
    return nil
  end
  return { indent = indent, checked = mark ~= " ", text = rest }
end

--- Add `item` to the `## iso` section of a list of lines (section created in date order).
---@param lines string[]
---@param iso string
---@param item string
---@return string[]? new_lines nil when the item is already in that section
function M.add_to_day(lines, iso, item)
  local doc = markdown.parse(table.concat(lines, "\n") .. "\n")
  local order = config.get().section_order
  if order == "auto" then
    order = markdown.detect_order(doc) or "oldest_first"
  end
  if archive.merge_section(doc, iso, { item }, order) == "skipped" then
    return nil
  end
  local out = vim.split(markdown.render(doc), "\n", { plain = true })
  if out[#out] == "" then
    table.remove(out)
  end
  return out
end

--- Append `items` under today's section of the file at `path` (created with `title` if missing).
---@param path string
---@param title string
---@param items string[]
---@return "file"|"buffer"|nil changed, integer added
local function add_items(path, title, items)
  if not fs.exists(path) then
    local ok, err = fs.write_file(path, title .. "\n")
    if not ok then
      error(err, 0)
    end
  end
  local today = date.today()
  local added = 0
  local ok, err, changed = fs.update_lines(path, function(lines)
    local current, touched = lines, false
    for _, item in ipairs(items) do
      local new = M.add_to_day(current, today, item)
      if new then
        current, touched = new, true
        added = added + 1
      end
    end
    return touched and current or nil
  end)
  if not ok then
    error(err, 0)
  end
  return changed, added
end

--- Log `items` (already formatted lines) under today's section in DONE.md.
---@param root string
---@param items string[]
---@return "file"|"buffer"|nil changed, integer added
function M.log_done(root, items)
  return add_items(config.path("done", root), "# DONE", items)
end

--- Capture `text` into INBOX under today's date, tagged with the active project.
---@param text string
---@param root string
---@param project? string
function M.capture(text, root, project)
  local item = "- [ ] " .. text
  if project and not text:find("#" .. project, 1, true) then
    item = item .. " #" .. project
  end
  local changed, added = add_items(config.path("inbox", root), "# INBOX", { item })
  if added == 0 then
    vim.notify("logpose: already in today's INBOX", vim.log.levels.INFO)
  elseif changed == "buffer" then
    vim.notify("logpose: captured to the INBOX buffer (unsaved)", vim.log.levels.INFO)
  else
    vim.notify("logpose: captured to INBOX", vim.log.levels.INFO)
  end
end

---@param path string
---@param key string
---@param root string
local function same_file(path, key, root)
  local a = vim.uv.fs_realpath(path) or fs.normalize(path)
  local target = config.path(key, root)
  local b = vim.uv.fs_realpath(target) or fs.normalize(target)
  return a == b
end

--- Mark tasks in lines `line1..line2` of the current buffer as done.
--- INBOX: moved to DONE. Other journal notes: checked off in place and logged in DONE with a link.
---@param root string
---@param line1 integer
---@param line2 integer
function M.done(root, line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    error("logpose: :Logpose done works on a journal file", 0)
  end
  local abs = fs.normalize(path)
  local real_root = fs.normalize(root)
  if not vim.startswith(vim.uv.fs_realpath(abs) or abs, (vim.uv.fs_realpath(real_root) or real_root) .. "/") then
    error("logpose: not a journal file (outside " .. vim.fn.fnamemodify(root, ":~") .. ")", 0)
  end
  if same_file(abs, "done", root) then
    vim.notify("logpose: already in DONE", vim.log.levels.INFO)
    return
  end

  local from_inbox = same_file(abs, "inbox", root)
  local was_modified = vim.bo[buf].modified
  local lines = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, false)
  local done_path = config.path("done", root)
  local items, rows, skipped, already = {}, {}, 0, 0
  for i, line in ipairs(lines) do
    local task = M.parse_task(line)
    if not task then
      skipped = skipped + 1
    elseif task.checked and not from_inbox then
      already = already + 1
    else
      local item = "- [x] " .. task.text
      if not from_inbox then
        local label = vim.fn.fnamemodify(abs, ":t:r")
        item = item .. " (" .. link.make(done_path, abs, label, root) .. ")"
      end
      table.insert(items, item)
      table.insert(rows, line1 + i - 1)
    end
  end

  if #items > 0 then
    add_items(done_path, "# DONE", items)
    -- Edit the current buffer through the API so `u` undoes it.
    for j = #rows, 1, -1 do
      local row = rows[j]
      if from_inbox then
        vim.api.nvim_buf_set_lines(buf, row - 1, row, false, {})
      else
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
        local checked = line:gsub("%[ %]", "[x]", 1)
        vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { checked })
      end
    end
    -- Keep disk consistent with DONE (unless the user already had unsaved edits here).
    if not was_modified then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
    end
  end

  local parts = {}
  if #items > 0 then
    table.insert(parts, ("%d task%s done"):format(#items, #items == 1 and "" or "s"))
  end
  if already > 0 then
    table.insert(parts, ("%d already checked"):format(already))
  end
  if skipped > 0 then
    table.insert(parts, ("skipped %d non-task line%s"):format(skipped, skipped == 1 and "" or "s"))
  end
  vim.notify("logpose: " .. table.concat(parts, ", "), vim.log.levels.INFO)
end

---@param opts logpose.CommandOpts
function M.capture_command(opts)
  local text = vim.trim(table.concat(opts.args, " "))
  config.with_root(ui.safely(function(root)
    local project = require("logpose.project").resolve(root)
    if text ~= "" then
      M.capture(text, root, project)
      return
    end
    local prompt = project and ("Capture (#" .. project .. "): ") or "Capture: "
    vim.ui.input(
      { prompt = prompt },
      ui.safely(function(input)
        input = input and vim.trim(input) or ""
        if input == "" then
          vim.notify("logpose: cancelled (empty input)", vim.log.levels.INFO)
          return
        end
        M.capture(input, root, project)
      end)
    )
  end))
end

---@param opts logpose.CommandOpts
function M.done_command(opts)
  local line1, line2 = opts.line1, opts.line2
  if opts.range == 0 or line1 == 0 then
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end
  local root = config.root()
  M.done(root, line1, line2)
end

return M

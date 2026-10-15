--- `:Logpose triage [filters]`: process open INBOX tasks one by one, oldest first.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local query = require("logpose.query")
local tasks = require("logpose.tasks")
local ui = require("logpose.util.ui")

local M = {}

--- Actions offered for each item. Editing actions keep the item; the others move on.
M.ACTIONS = {
  { key = "project", label = "p  project — add #project" },
  { key = "tag", label = "t  tag — add #tags" },
  { key = "due", label = "u  due — set due:date" },
  { key = "owner", label = "o  owner — add @owner" },
  { key = "move", label = "m  move — into a note" },
  { key = "done", label = "d  done" },
  { key = "someday", label = "s  someday — park under ## Someday" },
  { key = "drop", label = "x  drop — delete" },
  { key = "skip", label = "n  skip" },
  { key = "quit", label = "q  quit" },
}

M._drop_confirmed = false

---@class logpose.TriageSession
---@field root string
---@field queue logpose.Item[]  items with their original `line`
---@field i integer
---@field stats table<string, integer>

--- Read INBOX lines (from its buffer if loaded, so unsaved edits count).
---@param path string
---@return string[]
local function read(path)
  local buf = fs.find_buf(path)
  if buf then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local lines = fs.read_lines(path) or {}
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

--- Apply `fn(lines) -> lines` to INBOX: through its buffer when loaded (undoable, then saved if
--- it had no unsaved edits), else as a safe file write.
---@param path string
---@param fn fun(lines: string[]): string[]?
local function edit(path, fn)
  local buf = fs.find_buf(path)
  if buf then
    local was_modified = vim.bo[buf].modified
    local new = fn(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if new then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
      if not was_modified then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent write")
        end)
      end
    end
    return
  end
  local ok, err = fs.update_lines(path, fn)
  if not ok then
    error(err, 0)
  end
end

--- Line number of the item in `lines` (exact text, nearest to where it was).
---@param lines string[]
---@param item table
---@return integer?
local function locate(lines, item)
  local best, dist
  for i, l in ipairs(lines) do
    if l == item.line then
      local d = math.abs(i - item.lnum)
      if not dist or d < dist then
        best, dist = i, d
      end
    end
  end
  return best
end

--- Open INBOX tasks, oldest first, matching `args`.
---@param root string
---@param args string[]
---@return table[]
function M.collect(root, args)
  local path = config.path("inbox", root)
  local lines = read(path)
  local q = query.parse(args)
  local items = {}
  for _, it in ipairs(require("logpose.index").index_lines(path, lines, root)) do
    if it.kind == "task" and not it.checked and it.section ~= "someday" and query.match(it, q) then
      it.line = lines[it.lnum]
      table.insert(items, it)
    end
  end
  table.sort(items, function(a, b)
    if (a.date or "~") ~= (b.date or "~") then
      return (a.date or "~") < (b.date or "~")
    end
    return a.lnum < b.lnum
  end)
  return items
end

---@param line string
---@param text string
---@return string
local function append(line, text)
  return line:gsub("%s+$", "") .. " " .. text
end

---@param line string
---@param iso string
---@return string
function M.set_due(line, iso)
  if line:find("due:%S+") then
    return (line:gsub("due:%S+", "due:" .. iso, 1))
  end
  return append(line, "due:" .. iso)
end

--- Replace the item's line (re-located) with `new_line`, or delete it when nil.
---@param s logpose.TriageSession
---@param item table
---@param new_line? string
local function replace(s, item, new_line)
  local path = config.path("inbox", s.root)
  edit(path, function(lines)
    local idx = locate(lines, item)
    if not idx then
      error("logpose: the item is no longer in INBOX", 0)
    end
    if new_line then
      lines[idx] = new_line
      item.lnum = idx
    else
      table.remove(lines, idx)
    end
    return lines
  end)
  if new_line then
    item.line = new_line
    item.text = tasks.parse_task(new_line).text
  end
end

local next_item

---@param s logpose.TriageSession
local function finish(s)
  local parts = {}
  for _, k in ipairs({ "tagged", "moved", "done", "someday", "dropped", "skipped" }) do
    if (s.stats[k] or 0) > 0 then
      table.insert(parts, ("%d %s"):format(s.stats[k], k))
    end
  end
  local left = #M.collect(s.root, {})
  vim.notify(
    ("logpose: triage finished%s; %d left in INBOX"):format(
      #parts > 0 and (": " .. table.concat(parts, ", ")) or "",
      left
    ),
    vim.log.levels.INFO
  )
end

---@param s logpose.TriageSession
---@param key string
local function bump(s, key)
  s.stats[key] = (s.stats[key] or 0) + 1
end

--- Ask for input, then call `fn(value)` (skips on empty/cancel, re-prompting the item).
local function ask(s, prompt, fn)
  vim.ui.input(
    { prompt = prompt },
    ui.safely(function(value)
      value = value and vim.trim(value) or ""
      if value ~= "" then
        fn(value)
      end
      next_item(s, false)
    end)
  )
end

---@param s logpose.TriageSession
---@param item table
---@param key string
local function act(s, item, key)
  local root = s.root
  if key == "quit" then
    finish(s)
  elseif key == "skip" then
    bump(s, "skipped")
    next_item(s, true)
  elseif key == "project" then
    local projects = require("logpose.search").projects(root, require("logpose.index").build(root))
    local choices = vim.list_extend(vim.deepcopy(projects), { "New project…" })
    vim.ui.select(
      choices,
      { prompt = "Project for: " .. item.text },
      ui.safely(function(choice)
        if not choice then
          return next_item(s, false)
        end
        local function apply(name)
          local slug = require("logpose.project").normalize(name)
          if slug and not item.line:find("#" .. slug, 1, true) then
            replace(s, item, append(item.line, "#" .. slug))
            bump(s, "tagged")
          end
        end
        if choice == "New project…" then
          return ask(s, "Project name: ", apply)
        end
        apply(choice)
        next_item(s, false)
      end)
    )
  elseif key == "tag" then
    ask(s, "Tags (space separated): ", function(value)
      local line = item.line
      for word in value:gmatch("%S+") do
        local tag = "#" .. word:gsub("^#", "")
        if not line:find(tag, 1, true) then
          line = append(line, tag)
        end
      end
      replace(s, item, line)
      bump(s, "tagged")
    end)
  elseif key == "due" then
    ask(s, "Due (YYYY-MM-DD, +3d, tomorrow…): ", function(value)
      local iso = date.resolve(value)
      if not iso then
        vim.notify(("logpose: not a date: %q"):format(value), vim.log.levels.WARN)
        return
      end
      replace(s, item, M.set_due(item.line, iso))
      bump(s, "tagged")
    end)
  elseif key == "owner" then
    ask(s, "Owner: ", function(value)
      local owner = "@" .. value:gsub("^@", "")
      if not item.line:find(owner, 1, true) then
        replace(s, item, append(item.line, owner))
        bump(s, "tagged")
      end
    end)
  elseif key == "done" then
    tasks.log_done(root, { "- [x] " .. item.text })
    replace(s, item, nil)
    bump(s, "done")
    next_item(s, true)
  elseif key == "someday" then
    local path = config.path("inbox", root)
    edit(path, function(lines)
      local idx = locate(lines, item)
      if not idx then
        error("logpose: the item is no longer in INBOX", 0)
      end
      local line = table.remove(lines, idx)
      return require("logpose.notes.meeting").insert_under_heading(lines, "Someday", line, "\0") or lines
    end)
    bump(s, "someday")
    next_item(s, true)
  elseif key == "drop" then
    local function drop()
      replace(s, item, nil)
      bump(s, "dropped")
      next_item(s, true)
    end
    if M._drop_confirmed then
      return drop()
    end
    vim.ui.select(
      { "Drop", "Keep" },
      { prompt = "Delete this item? (asked once per session)" },
      ui.safely(function(c)
        if c == "Drop" then
          M._drop_confirmed = true
          return drop()
        end
        next_item(s, false)
      end)
    )
  elseif key == "move" then
    M.move(s, item)
  end
end

--- Move the item into a note: under `## Action items`, else `## Notes`, else at the end.
---@param s logpose.TriageSession
---@param item table
function M.move(s, item)
  local root = s.root
  local notes = vim.tbl_filter(function(it)
    return it.kind == "note" and not vim.tbl_contains({ "inbox", "done", "archive" }, it.note_type)
  end, require("logpose.index").build(root))
  local search = require("logpose.search")
  search.sort(notes)
  local entries = vim.tbl_map(function(it)
    return { display = search.display(it), file = it.file, lnum = 1, item = it }
  end, notes)
  require("logpose.picker").pick(entries, {
    prompt = "Move to note",
    cwd = root,
    on_choice = ui.safely(function(choice)
      local target = choice.file
      local line = "- [ ] " .. item.text
      local ok, err = fs.update_lines(target, function(lines)
        local heading
        for _, name in ipairs({ "Action items", "Notes" }) do
          if require("logpose.standup").section_range(lines, name) then
            heading = name
            break
          end
        end
        if heading then
          return require("logpose.notes.meeting").insert_under_heading(lines, heading, line, "\0") or lines
        end
        local out = vim.list_extend({}, lines)
        table.insert(out, line)
        return out
      end)
      if not ok then
        error(err, 0)
      end
      replace(s, item, nil)
      bump(s, "moved")
      next_item(s, true)
    end),
  })
end

--- Show the action menu for the current item (advancing first when `advance`).
---@param s logpose.TriageSession
---@param advance boolean
next_item = function(s, advance)
  if advance then
    s.i = s.i + 1
  end
  local item = s.queue[s.i]
  if not item then
    return finish(s)
  end
  vim.ui.select(
    M.ACTIONS,
    {
      prompt = ("Triage %d/%d%s: %s"):format(s.i, #s.queue, item.date and (" (" .. item.date .. ")") or "", item.text),
      format_item = function(a)
        return a.label
      end,
    },
    ui.safely(function(choice)
      if not choice then
        return finish(s)
      end
      act(s, item, choice.key)
    end)
  )
end

---@param opts logpose.CommandOpts
function M.command(opts)
  local args = opts.args
  query.parse(args) -- validate before any prompt
  config.with_root(ui.safely(function(root)
    if config.get().tasks.mode == "files" then
      -- With task files, triage happens on the board, starting at the column captures land in.
      require("logpose.board").open_board(
        root,
        { filter = table.concat(args, " "), column = config.get().tasks.capture_status }
      )
      return
    end
    local queue = M.collect(root, args)
    if #queue == 0 then
      vim.notify("logpose: INBOX is clear", vim.log.levels.INFO)
      return
    end
    next_item({ root = root, queue = queue, i = 1, stats = {} }, false)
  end))
end

function M.complete(arglead, args)
  return require("logpose.search").complete(arglead, vim.list_extend({ "tasks" }, args))
end

return M

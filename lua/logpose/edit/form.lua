--- The frontmatter editor's window: one line per field holding just its value, with the field
--- names drawn beside them (so they can't be edited), a hint in each empty field, a check of
--- every value as you type, and a summary of what saving will do.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fields = require("logpose.edit.fields")
local save = require("logpose.edit.save")
local ui = require("logpose.util.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("logpose.edit")
-- one invisible mark per field line, to tell which field a line was after lines are deleted
-- or pasted
local track = vim.api.nvim_create_namespace("logpose.edit.track")

---@class logpose.EditForm
---@field buf integer
---@field win integer
---@field model logpose.EditModel
---@field ctx logpose.EditCtx
---@field label_w integer
---@field marks integer[]
---@field result? logpose.EditResult
---@field help boolean
---@field links? integer
---@field on_save? fun(path: string|string[], keys: string[])
---@field accepted? string  the line as a completion left it (the menu isn't reopened for it)

---@type table<integer, logpose.EditForm>
M.forms = {}

local function define_highlights()
  for name, link in pairs({
    LogposeEditLabel = "Identifier",
    LogposeEditHint = "Comment",
    LogposeEditNote = "Comment",
    LogposeEditError = "DiagnosticError",
    LogposeEditEffect = "DiagnosticInfo",
    LogposeEditInfo = "NonText",
  }) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

M.HELP = {
  { "<Tab>", "complete, or go to the next field" },
  { "<CR>", "pick a value (status, project, type, tags…)" },
  { "<C-a> <C-x>", "next / previous value; a day later / earlier" },
  { "dd", "clear a field" },
  { "+", "add a field" },
  { "<C-s>  :w", "save" },
  { "q", "cancel" },
}

-- Candidates ---------------------------------------------------------------------------------

--- Candidates for a field, as complete-items, best matches first.
---@param root string
---@param kind string
---@param key string
---@param partial string
---@return table[]
function M.candidates(root, kind, key, partial)
  local items = {}
  local function add(word, menu)
    table.insert(items, { word = word, menu = menu })
  end
  if key == "project" then
    local project = require("logpose.project")
    for _, name in ipairs(project.known(root)) do
      local title = project.title(root, name)
      add(name, title ~= name and title or nil)
    end
  elseif key == "status" and kind == "task" then
    for _, c in ipairs(require("logpose.taskfile").columns()) do
      add(c.key, c.label)
    end
  elseif key == "tags" then
    local index = require("logpose.index")
    for _, c in ipairs(index.tag_counts(index.build(root))) do
      add(c.tag, tostring(c.count))
    end
  elseif key == "attendees" or key == "with" then
    for _, p in ipairs(require("logpose.people").known(root)) do
      add(p.name, ("%d notes"):format(p.count))
    end
  elseif key == "type" and kind == "meeting" then
    for name, spec in pairs(config.get().meeting_types) do
      if spec then
        add(name, spec.label)
      end
    end
    table.sort(items, function(a, b)
      return a.word < b.word
    end)
  elseif fields.DATES[key] then
    local today = date.today()
    for d = 0, 13 do
      local iso = date.add_days(today, d)
      local label = d == 0 and "today" or d == 1 and "tomorrow" or ("in %dd"):format(d)
      add(iso, date.weekday_name(iso):sub(1, 3) .. " · " .. label)
    end
  elseif key == "paths" then
    for _, dir in ipairs(vim.fn.getcompletion(partial ~= "" and partial or "~/", "dir")) do
      add((dir:gsub("/$", "")), nil)
    end
  end
  if partial == "" or key == "paths" then
    return items
  end
  local p = partial:lower()
  local starts, contains = {}, {}
  for _, it in ipairs(items) do
    local w = it.word:lower()
    if vim.startswith(w, p) then
      table.insert(starts, it)
    elseif w:find(p, 1, true) or (it.menu and it.menu:lower():find(p, 1, true)) then
      table.insert(contains, it)
    end
  end
  return vim.list_extend(starts, contains)
end

---@param buf? integer
---@return logpose.EditForm?
local function form_of(buf)
  return M.forms[buf or vim.api.nvim_get_current_buf()]
end

--- The field on a (1-based) row.
---@param f logpose.EditForm
---@param row integer
---@return string?
local function key_at(f, row)
  return f.model.keys[row]
end

--- What to complete at the cursor: the 0-based column where the word starts, and the items.
---@param f logpose.EditForm
---@return integer?, table[]?
local function at_cursor(f)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local key = key_at(f, row)
  if not key then
    return nil
  end
  local before = (vim.api.nvim_buf_get_lines(f.buf, row - 1, row, false)[1] or ""):sub(1, col)
  local start, partial = 0, before
  if fields.LISTS[key] then
    if key == "tags" and f.model.bulk and vim.trim(before):match("^[+-]") then
      -- "+a -b": complete the tag after the last sign
      local s, word = before:match("()[+-]#?([%w_%-/]*)$")
      if not s then
        return nil
      end
      start, partial = #before - #word, word
    else
      local last = before:match("^.*,%s*()")
      if last then
        start, partial = last - 1, before:sub(last)
      end
      partial = partial:gsub("^%s+", "")
      start = #before - #partial
    end
  else
    partial = vim.trim(before)
    start = #before - #partial
  end
  local items = M.candidates(f.model.root, f.model.kind, key, partial)
  if fields.LISTS[key] then
    -- don't offer what's already in the list
    local have = {}
    for item in before:gmatch("[^,%s]+") do
      have[(item:gsub("^[+-]?#?", "")):lower()] = true
    end
    items = vim.tbl_filter(function(it)
      return not have[it.word:lower()] or it.word:lower() == partial:lower()
    end, items)
  end
  return start, items
end

--- 'omnifunc' for the form (<C-x><C-o>).
function M.omnifunc(findstart, _)
  local f = form_of()
  local start, items
  if f then
    start, items = at_cursor(f)
  end
  if findstart == 1 then
    return start or -3
  end
  return items or {}
end

--- Show the completion menu for the cursor position. Returns whether it opened.
---@param f logpose.EditForm
---@return boolean
local function popup(f)
  local start, items = at_cursor(f)
  if not start or not items or #items == 0 then
    return false
  end
  vim.fn.complete(start + 1, items)
  return true
end

-- Drawing ------------------------------------------------------------------------------------

---@param f logpose.EditForm
---@param key string
---@return string
local function label(f, key)
  return key .. string.rep(" ", f.label_w - vim.fn.strdisplaywidth(key))
end

--- Put the field marks back on rows 0..n-1.
---@param f logpose.EditForm
local function place_marks(f)
  for i = 1, #f.model.keys do
    f.marks[i] = vim.api.nvim_buf_set_extmark(f.buf, track, i - 1, 0, { id = f.marks[i] })
  end
end

--- After a change that added or removed lines (dd, a paste, J), give each field its line
--- back: a deleted line clears its field, extra lines join the field above them.
---@param f logpose.EditForm
---@return boolean repaired
function M.repair(f)
  local n = #f.model.keys
  local lines = vim.api.nvim_buf_get_lines(f.buf, 0, -1, false)
  if #lines == n then
    return false
  end
  local owner, first = {}, nil
  for i = 1, n do
    local pos = vim.api.nvim_buf_get_extmark_by_id(f.buf, track, f.marks[i], {})
    -- a mark pushed off column 0 belonged to a line that was deleted or joined
    if pos[1] and pos[2] == 0 then
      owner[pos[1]] = i -- the last field wins: an earlier one sharing the row was deleted
    end
  end
  local values = {}
  for i = 1, n do
    values[i] = ""
  end
  local current, pre = nil, {}
  for r = 0, #lines - 1 do
    local text = lines[r + 1]
    local i = owner[r]
    if i then
      current = i
      first = first or i
      values[i] = text
    elseif vim.trim(text) ~= "" then
      if current then
        values[current] = vim.trim(values[current] .. " " .. vim.trim(text))
      else
        table.insert(pre, vim.trim(text))
      end
    end
  end
  if #pre > 0 then
    local target = first or 1
    values[target] = vim.trim(table.concat(pre, " ") .. " " .. values[target])
  end
  local win = vim.fn.bufwinid(f.buf)
  local cursor_field = current or 1
  if win ~= -1 then
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1
    for r = row, 0, -1 do
      if owner[r] then
        cursor_field = owner[r]
        break
      end
    end
  end
  -- part of the change that caused it, so one `u` undoes both
  pcall(vim.cmd, "silent! undojoin")
  vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, values)
  place_marks(f)
  if win ~= -1 then
    pcall(vim.api.nvim_win_set_cursor, win, { cursor_field, 0 })
  end
  return true
end

--- The form's text per field.
---@param f logpose.EditForm
---@return table<string, string>
local function texts(f)
  local lines = vim.api.nvim_buf_get_lines(f.buf, 0, -1, false)
  local out = {}
  for i, key in ipairs(f.model.keys) do
    out[key] = lines[i] or ""
  end
  return out
end

--- Check every field and redraw the labels, hints, messages and the summary.
---@param f logpose.EditForm
function M.render(f)
  if not vim.api.nvim_buf_is_valid(f.buf) then
    return
  end
  M.repair(f)
  local model = f.model
  local t = texts(f)
  local r = fields.collect(model, t, f.ctx)
  f.result = r
  vim.api.nvim_buf_clear_namespace(f.buf, ns, 0, -1)
  local n = #model.keys
  for i, key in ipairs(model.keys) do
    local row = i - 1
    vim.api.nvim_buf_set_extmark(f.buf, ns, row, 0, {
      virt_text = { { label(f, key), "LogposeEditLabel" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
    local eol, pad = nil, "  "
    if r.errors[key] then
      eol = { "✗ " .. r.errors[key], "LogposeEditError" }
    elseif vim.trim(t[key]) == "" then
      local hint = (model.bulk and fields.BULK_HINTS[key]) or fields.HINTS[key]
      eol, pad = hint and { hint, "LogposeEditHint" }, "" -- where the value goes, like a placeholder
    elseif r.notes[key] then
      eol = { r.notes[key], "LogposeEditNote" }
    end
    if eol then
      vim.api.nvim_buf_set_extmark(f.buf, ns, row, 0, {
        virt_text = { { pad }, eol },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end

  -- below the fields: what saving will do, logpose's own fields, the keys
  local indent = { string.rep(" ", f.label_w) }
  local below = { { { "" } } }
  local effects = fields.effects(model, r, function()
    if f.links == nil and model.path then
      f.links = save.links_to(model.root, model.path)
    end
    return f.links or 0
  end)
  if r.nerrors > 0 then
    table.insert(below, {
      indent,
      { ("✗ fix %d field%s to save"):format(r.nerrors, r.nerrors == 1 and "" or "s"), "LogposeEditError" },
    })
  end
  if #effects == 0 then
    table.insert(below, { indent, { "no changes yet", "LogposeEditInfo" } })
  else
    table.insert(below, { indent, { "saving will:", "LogposeEditInfo" } })
    for _, e in ipairs(effects) do
      table.insert(below, { indent, { "• " .. e, "LogposeEditEffect" } })
    end
  end
  if #model.info > 0 then
    table.insert(below, { { "" } })
    for _, it in ipairs(model.info) do
      table.insert(below, { { label(f, it.key), "LogposeEditInfo" }, { it.value, "LogposeEditInfo" } })
    end
  end
  if f.help then
    table.insert(below, { { "" } })
    for _, h in ipairs(M.HELP) do
      table.insert(below, { { label(f, h[1]), "LogposeEditLabel" }, { h[2], "LogposeEditHint" } })
    end
  end
  vim.api.nvim_buf_set_extmark(f.buf, ns, n - 1, 0, { virt_lines = below })
  place_marks(f)

  -- Resizing the window closes an open completion menu: wait until it's closed.
  if vim.api.nvim_win_is_valid(f.win) and vim.fn.pumvisible() == 0 then
    local height = math.min(n + #below, math.max(6, vim.o.lines - 6))
    if vim.api.nvim_win_get_height(f.win) ~= height then
      local cfg = vim.api.nvim_win_get_config(f.win)
      cfg.height = height
      cfg.row = math.floor((vim.o.lines - 2 - height) / 2)
      vim.api.nvim_win_set_config(f.win, cfg)
    end
  end
end

-- Actions ------------------------------------------------------------------------------------

--- Move to field `row` (clamped), at the end of its value; stays in insert mode if in it.
---@param f logpose.EditForm
---@param row integer
local function goto_field(f, row)
  row = math.max(1, math.min(row, #f.model.keys))
  local line = vim.api.nvim_buf_get_lines(f.buf, row - 1, row, false)[1] or ""
  vim.api.nvim_win_set_cursor(f.win, { row, #line })
end

--- Replace field `row`'s text.
---@param f logpose.EditForm
---@param row integer
---@param text string
local function set_field(f, row, text)
  vim.api.nvim_buf_set_lines(f.buf, row - 1, row, false, { text })
  M.render(f)
  goto_field(f, row)
end

--- Next/previous field (insert-mode <CR>, <Tab> with nothing to complete, normal o/O).
---@param delta integer
function M.next_field(delta)
  local f = form_of()
  if f then
    goto_field(f, vim.api.nvim_win_get_cursor(0)[1] + delta)
  end
end

--- Insert-mode <Tab>: open the menu if the field has suggestions, else go to the next field.
---@param delta integer
function M.tab(delta)
  local f = form_of()
  if not f then
    return
  end
  if delta > 0 and popup(f) then
    -- <Tab> completes: the first match is picked right away (<Tab> again for the next)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "in", false)
    return
  end
  M.next_field(delta)
end

--- The values `<C-a>`/`<C-x>` cycle through for a field.
---@param f logpose.EditForm
---@param key string
---@return string[]
local function choices(f, key)
  local words = vim.tbl_map(function(it)
    return it.word
  end, M.candidates(f.model.root, f.model.kind, key, ""))
  if key == "project" then
    table.sort(words)
    table.insert(words, 1, "")
  end
  return words
end

--- `<C-a>`/`<C-x>`: the next/previous value of a field with a fixed set, a day later/earlier
--- for a date. Anything else gets Vim's own increment.
---@param delta integer
function M.cycle(delta)
  local f = form_of()
  if not f then
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local key = key_at(f, row)
  local text = vim.trim(vim.api.nvim_buf_get_lines(f.buf, row - 1, row, false)[1] or "")
  local count = vim.v.count1
  if key and fields.DATES[key] then
    local resolve = key == "due" and date.resolve_due or date.resolve
    local cur = resolve(text)
    set_field(f, row, cur and date.add_days(cur, delta * count) or date.today())
  elseif key and fields.CHOICES[key] and not (key == "status" and f.model.kind ~= "task") then
    local words = choices(f, key)
    if #words == 0 then
      return
    end
    local value = fields.check(f.model.kind, key, text, f.ctx)
    local idx = 0
    for i, w in ipairs(words) do
      if w == value then
        idx = i
      end
    end
    if idx == 0 and delta < 0 then
      idx = 1
    end
    set_field(f, row, words[((idx - 1 + delta * count) % #words) + 1])
  else
    local keys = vim.api.nvim_replace_termcodes(delta > 0 and "<C-a>" or "<C-x>", true, false, true)
    vim.api.nvim_feedkeys((vim.v.count > 0 and tostring(vim.v.count) or "") .. keys, "n", false)
  end
end

--- Normal-mode <CR>: pick a value for a field that has suggestions (a list field gets the
--- item added), or start typing at the end of the value.
function M.pick()
  local f = form_of()
  if not f then
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local key = key_at(f, row)
  local items = key and M.candidates(f.model.root, f.model.kind, key, "") or {}
  if key == "project" then
    table.insert(items, 1, { word = f.model.bulk and "none" or "", menu = "no project" })
  end
  if #items == 0 then
    vim.cmd("startinsert!")
    return
  end
  local text = vim.api.nvim_buf_get_lines(f.buf, row - 1, row, false)[1] or ""
  vim.ui.select(items, {
    prompt = key,
    format_item = function(it)
      local w = it.word ~= "" and it.word or "—"
      return it.menu and (w .. "  " .. it.menu) or w
    end,
  }, function(it)
    if not it or not vim.api.nvim_buf_is_valid(f.buf) then
      return
    end
    local value = it.word
    if fields.LISTS[key] then
      local items_now = fields.split(key, text)
      for _, x in ipairs(items_now) do
        if x:lower() == value:lower() then
          value = nil
        end
      end
      if value then
        table.insert(items_now, value)
      end
      value = table.concat(items_now, ", ")
    end
    if vim.api.nvim_win_is_valid(f.win) then
      vim.api.nvim_set_current_win(f.win)
    end
    set_field(f, row, value)
  end)
end

--- `+`: add a field the form doesn't show.
function M.add_field()
  local f = form_of()
  if not f or f.model.bulk then
    return
  end
  vim.ui.input({ prompt = "New field: " }, function(key)
    key = key and vim.trim(key) or ""
    if key == "" or not vim.api.nvim_buf_is_valid(f.buf) then
      return
    end
    if not key:match("^%a[%w_%-]*$") then
      ui.notify(("logpose: %q isn't a field name (letters, digits, - and _)"):format(key), vim.log.levels.WARN)
      return
    end
    if fields.MANAGED[key] or vim.tbl_contains(f.model.keys, key) then
      ui.notify(("logpose: %s is already there or kept by logpose"):format(key), vim.log.levels.WARN)
      return
    end
    table.insert(f.model.keys, key)
    f.model.initial[key] = ""
    f.label_w = math.max(f.label_w, #key + 2)
    vim.api.nvim_buf_set_lines(f.buf, -1, -1, false, { "" })
    f.marks[#f.model.keys] = nil
    M.render(f)
    if vim.api.nvim_win_is_valid(f.win) then
      vim.api.nvim_set_current_win(f.win)
      goto_field(f, #f.model.keys)
      vim.cmd("startinsert!")
    end
  end)
end

---@param f logpose.EditForm
local function close(f)
  if vim.api.nvim_win_is_valid(f.win) then
    vim.api.nvim_win_close(f.win, true)
  end
end

--- Save: refuses (and shows the field) while something doesn't check out.
---@param f logpose.EditForm
function M.save(f)
  M.render(f)
  local r = f.result
  if r.nerrors > 0 then
    for i, key in ipairs(f.model.keys) do
      if r.errors[key] then
        goto_field(f, i)
        error(("logpose: %s: %s"):format(key, r.errors[key]), 0)
      end
    end
  end
  local model = f.model
  if model.bulk then
    local updated, keys = save.bulk(model, r.changed)
    vim.bo[f.buf].modified = false
    close(f)
    if #keys == 0 then
      ui.notify("logpose: nothing changed", vim.log.levels.INFO)
    else
      ui.notify(
        ("logpose: updated %s on %d of %d tasks"):format(table.concat(keys, ", "), updated, #model.bulk.paths),
        vim.log.levels.INFO
      )
    end
    if f.on_save then
      f.on_save(model.bulk.paths, keys)
    end
    return
  end
  local path, keys = save.note(model.root, model.path, model.kind, r.changed)
  vim.bo[f.buf].modified = false
  close(f)
  if #keys == 0 then
    ui.notify("logpose: nothing changed", vim.log.levels.INFO)
  else
    ui.notify(("logpose: updated %s"):format(table.concat(keys, ", ")), vim.log.levels.INFO)
  end
  if f.on_save then
    f.on_save(path, keys)
  end
end

-- The window ---------------------------------------------------------------------------------

--- Show the form for a model. `opts.on_save(path_or_paths, keys)` runs after a save.
---@param model logpose.EditModel
---@param opts? { on_save?: fun(path: string|string[], keys: string[]) }
---@return integer win
function M.show(model, opts)
  opts = opts or {}
  define_highlights()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for _, key in ipairs(model.keys) do
    table.insert(lines, model.initial[key] or "")
  end
  -- the starting text isn't an undo step: `u` can't empty the form
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = -123456 -- back to the global setting
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modified = false
  pcall(vim.api.nvim_buf_set_name, buf, "logpose://edit/" .. (model.path and vim.fs.basename(model.path) or "tasks"))
  vim.bo[buf].filetype = "logpose-edit"
  vim.bo[buf].omnifunc = "v:lua.require'logpose.edit.form'.omnifunc"
  vim.b[buf].logpose_edit = { root = model.root, kind = model.kind, path = model.path }
  -- our own popup, not a completion plugin's
  vim.b[buf].completion = false -- blink.cmp
  if package.loaded["cmp"] then
    pcall(function()
      require("cmp").setup.buffer({ enabled = false })
    end)
  end

  local label_w = 10
  for _, key in ipairs(model.keys) do
    label_w = math.max(label_w, #key + 2)
  end
  for _, it in ipairs(model.info) do
    label_w = math.max(label_w, #it.key + 2)
  end
  local longest = 0
  for _, l in ipairs(lines) do
    longest = math.max(longest, vim.fn.strdisplaywidth(l))
  end
  local width = math.min(math.max(72, label_w + longest + 30), math.max(40, vim.o.columns - 6))
  local title = model.bulk and (" Edit " .. model.title .. " ")
    or (" Edit · " .. require("logpose.board.text").fit(model.title, width - 12):gsub("%s+$", "") .. " ")
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - 2 - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = #lines,
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = " <C-s> save · q cancel · ? keys ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
  vim.wo[win].list = false
  vim.wo[win].spell = false

  ---@type logpose.EditForm
  local f = {
    buf = buf,
    win = win,
    model = model,
    ctx = fields.context(model.root),
    label_w = label_w,
    marks = {},
    help = false,
    on_save = opts.on_save,
  }
  M.forms[buf] = f
  M.render(f)

  -- completeopt is global on Neovim 0.10: set it while the form has focus
  local saved_cot
  local group = vim.api.nvim_create_augroup("logpose.edit." .. buf, { clear = true })
  local function enter()
    saved_cot = saved_cot or vim.o.completeopt
    vim.o.completeopt = "menuone,noinsert,noselect"
  end
  local function leave()
    if saved_cot then
      vim.o.completeopt = saved_cot
      saved_cot = nil
    end
  end
  enter()
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, { group = group, buffer = buf, callback = enter })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, { group = group, buffer = buf, callback = leave })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      leave()
      M.forms[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = buf,
    callback = function()
      M.render(f)
      local line = vim.api.nvim_get_current_line()
      if f.accepted == line then
        return -- the text a choice just put there: don't offer it again
      end
      f.accepted = nil
      if vim.fn.pumvisible() == 0 then
        popup(f)
      end
    end,
  })
  -- the menu closed: catch up on a resize skipped while it was open
  vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave" }, {
    group = group,
    buffer = buf,
    callback = function(ev)
      if ev.event == "CompleteDone" then
        -- an item was chosen: the menu stays closed until something new is typed
        local item = vim.v.completed_item
        f.accepted = (type(item) == "table" and item.word) and vim.api.nvim_get_current_line() or nil
      end
      vim.schedule(function()
        if M.forms[buf] then
          M.render(f)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedP" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.render(f)
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = ui.safely(function()
      M.save(f)
    end),
  })

  local function map(modes, lhs, rhs, desc, expr)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc, expr = expr })
  end
  map({ "n", "i" }, "<C-s>", function()
    vim.cmd("stopinsert")
    ui.safely(M.save)(f)
  end, "Save")
  map("n", "q", function()
    close(f)
  end, "Cancel")
  map("n", "<Esc>", function()
    close(f)
  end, "Cancel")
  map("n", "<CR>", M.pick, "Pick a value")
  map("n", "o", function()
    M.next_field(1)
    vim.cmd("startinsert!")
  end, "Next field")
  map("n", "O", function()
    M.next_field(-1)
    vim.cmd("startinsert!")
  end, "Previous field")
  map("n", "<C-a>", function()
    M.cycle(1)
  end, "Next value")
  map("n", "<C-x>", function()
    M.cycle(-1)
  end, "Previous value")
  map("n", "+", M.add_field, "Add a field")
  map("n", "?", function()
    f.help = not f.help
    M.render(f)
  end, "Keys")
  map("i", "<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Cmd>lua require('logpose.edit.form').tab(1)<CR>"
  end, "Complete or next field", true)
  map("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<Cmd>lua require('logpose.edit.form').tab(-1)<CR>"
  end, "Previous", true)
  map("i", "<CR>", function()
    if vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected ~= -1 then
      return "<C-y>"
    end
    return "<Cmd>lua require('logpose.edit.form').next_field(1)<CR>"
  end, "Accept or next field", true)

  -- start on the first value
  goto_field(f, 1)
  return win
end

return M

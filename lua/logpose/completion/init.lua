--- What the completion sources (blink.cmp, nvim-cmp) offer in a journal note:
---   `[[`                          notes and tasks to link (`links.complete_items`)
---   `attendees:` / `with:` lines  people, in the frontmatter, after each comma
---   `@` in the text               people, as `@handle`
--- People match any part of the name, accents ignored, the note's project's people first.
---
--- It works with no setup: in a journal note, logpose adds its source to blink.cmp or nvim-cmp
--- (whichever is loaded) for markdown, and without either it opens Neovim's own menu.
local config = require("logpose.config")

local M = {}

--- The frontmatter's closing row (1-based) of a buffer, or nil.
---@param bufnr integer
---@return integer?
local function fm_close(bufnr)
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if first ~= "---" then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 1, math.min(80, vim.api.nvim_buf_line_count(bufnr)), false)
  for i, l in ipairs(lines) do
    if l == "---" then
      return i + 1
    end
  end
  return nil
end

--- A name as a YAML list item: quoted when YAML would read it otherwise.
---@param name string
---@return string
local function yaml_item(name)
  if name:find("[,:%[%]\"'#{}]") or name:find("^[%-?&*!|>%%@`]") then
    return require("logpose.frontmatter").quote(name)
  end
  return name
end

---@param p logpose.Person
---@param i integer
---@param new_text string
---@param range table
---@param filter string
---@return table
local function person_item(p, i, new_text, range, filter)
  local people = require("logpose.people")
  return {
    label = p.name,
    detail = people.describe(p),
    kind = 12, -- Value
    filterText = filter,
    sortText = ("%05d"):format(i),
    textEdit = { newText = new_text, range = range },
  }
end

--- Completion items for the text before the cursor.
---@param line string the current line
---@param col integer cursor column (0-based, bytes)
---@param row integer cursor row (0-based)
---@param bufnr integer
---@return table[]
function M.items(line, col, row, bufnr)
  local source = vim.api.nvim_buf_get_name(bufnr)
  local links = require("logpose.links").complete_items(line, col, row, source)
  if #links > 0 then
    return links
  end
  local root = config.resolve_root()
  if not root then
    return {}
  end
  local before = line:sub(1, col)
  local people = require("logpose.people")
  local close = fm_close(bufnr)
  local in_fm = close and row + 1 < close
  local project
  if close then
    project = require("logpose.index").frontmatter(vim.api.nvim_buf_get_lines(bufnr, 0, close, false)).project
    project = type(project) == "string" and project ~= "" and require("logpose.project").normalize(project) or nil
  end
  local out = {}
  if in_fm then
    local key, rest = before:match("^(%w+):%s*(.*)$")
    if key ~= "attendees" and key ~= "with" then
      return {}
    end
    local partial = rest:match("[,%[]%s*([^,%[]*)$") or rest
    partial = partial:gsub("^[\"']", "")
    local start = col - #partial
    local known = people.known(root)
    local have = {}
    local done = rest:sub(1, #rest - #partial) -- the names before the one being typed
    for name in done:gsub("[%[%]\"']", ""):gmatch("[^,]+") do
      local p = people.find(known, name)
      if p then
        have[p] = true
      end
    end
    local range = { start = { line = row, character = start }, ["end"] = { line = row, character = col } }
    local i = 0
    for _, p in ipairs(people.match(known, partial, project)) do
      if not have[p] then
        i = i + 1
        local name = key == "with" and p.name or yaml_item(p.name)
        table.insert(out, person_item(p, i, name, range, p.name .. " " .. people.plain(p.name)))
      end
    end
    return out
  end
  -- @mentions in the text
  local at, handle = before:match("()@(" .. require("logpose.util.text").HANDLE_CHARS .. "*)$")
  if not at or (at > 1 and not before:sub(at - 1, at - 1):match("[%s%(%[,;]")) then
    return {}
  end
  local range = { start = { line = row, character = at - 1 }, ["end"] = { line = row, character = col } }
  for i, p in ipairs(people.match(people.known(root), handle, project)) do
    table.insert(out, person_item(p, i, "@" .. p.slug, range, "@" .. p.slug .. " " .. people.plain(p.name)))
  end
  return out
end

--- Characters that should open the menu.
M.TRIGGERS = { "[", "@", "," }

local hooked = {} ---@type table<string, boolean>

--- blink.cmp: the "logpose" provider for markdown, unless your config has it already.
---@return boolean hooked
local function hook_blink()
  if hooked.blink then
    return true
  end
  local ok, blink = pcall(require, "blink.cmp")
  if not ok or type(blink.add_source_provider) ~= "function" or type(blink.add_filetype_source) ~= "function" then
    return false
  end
  local cfg_ok, cfg = pcall(require, "blink.cmp.config")
  local sources = cfg_ok and type(cfg) == "table" and cfg.sources or {}
  if not (sources.providers or {}).logpose then
    local added = pcall(blink.add_source_provider, "logpose", {
      name = "logpose",
      module = "logpose.completion.blink",
    })
    if not added then
      return false
    end
  end
  local function lists(v)
    return type(v) == "table" and vim.tbl_contains(v, "logpose")
  end
  if not lists(sources.default) and not lists((sources.per_filetype or {}).markdown) then
    pcall(blink.add_filetype_source, "markdown", "logpose")
  end
  hooked.blink = true
  return true
end

--- nvim-cmp: the "logpose" source in this buffer's sources, unless they have it already.
---@param buf integer
---@return boolean hooked
local function hook_cmp(buf)
  local ok, cmp = pcall(require, "cmp")
  if not ok or type(cmp.get_config) ~= "function" then
    return false
  end
  require("logpose.completion.cmp").register()
  local sources = vim.deepcopy(cmp.get_config().sources or {})
  for _, src in ipairs(sources) do
    if src.name == "logpose" then
      return true
    end
  end
  table.insert(sources, { name = "logpose", group_index = (sources[1] or {}).group_index })
  vim.api.nvim_buf_call(buf, function()
    cmp.setup.buffer({ sources = sources })
  end)
  return true
end

--- Neovim's own menu, for when there's no completion plugin: opened as you type after `@`, `[[`
--- or in `attendees:`.
---@param buf integer
local function native(buf)
  local group = vim.api.nvim_create_augroup("logpose.completion.native." .. buf, { clear = true })
  local saved
  local function enter()
    saved = saved or vim.o.completeopt -- the menu mustn't type for you as it opens
    vim.o.completeopt = "menuone,noinsert,noselect"
  end
  vim.api.nvim_create_autocmd("InsertEnter", { group = group, buffer = buf, callback = enter })
  if vim.fn.mode() == "i" then
    enter() -- already typing: this Insert mode counts too
  end
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      if saved then
        vim.o.completeopt, saved = saved, nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = buf,
    callback = function()
      if package.loaded["blink.cmp"] or package.loaded["cmp"] then
        return -- a completion plugin arrived after all
      end
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local ok, items = pcall(M.items, line, col, row - 1, buf)
      if not ok or #items == 0 then
        return
      end
      local start = items[1].textEdit.range.start.character
      local words = {}
      for _, it in ipairs(items) do
        table.insert(words, { word = it.textEdit.newText, abbr = it.label, menu = it.detail, dup = 1 })
      end
      vim.fn.complete(start + 1, words)
    end,
  })
end

--- Completion in a journal note, with whatever you have: blink.cmp, nvim-cmp or neither.
---@param buf integer
function M.attach(buf)
  local fs = require("logpose.util.fs")
  local root = config.resolve_root(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if not root or name == "" or not fs.inside(name, root) or vim.b[buf].logpose_completion then
    return
  end
  vim.b[buf].logpose_completion = true
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = buf,
    once = true,
    callback = function()
      -- after the plugins that load on InsertEnter have set themselves up
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if package.loaded["blink.cmp"] and hook_blink() then
          return
        end
        if package.loaded["cmp"] and hook_cmp(buf) then
          return
        end
        native(buf)
      end)
    end,
  })
end

function M.setup_autocmd()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("logpose.completion", { clear = true }),
    pattern = "markdown",
    callback = function(ev)
      pcall(M.attach, ev.buf)
    end,
  })
end

return M

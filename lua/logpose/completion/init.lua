--- What the completion sources (blink.cmp, nvim-cmp) offer in a journal note:
---   `[[`                          notes and tasks to link (`links.complete_items`)
---   `attendees:` / `with:` lines  people, in the frontmatter, after each comma
---   `@` in the text               people, as `@handle`
--- People match any part of the name, accents ignored, the note's project's people first.
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
  local at, handle = before:match("()@([%w_%.%-]*)$")
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

return M

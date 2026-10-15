--- Configuration: defaults, merging, validation and journal-root resolution.
local fs = require("logpose.util.fs")

local M = {}

---@class logpose.Config
M.defaults = {
  --- Absolute path to the journal repo (recommended). `~` is expanded.
  ---@type string?
  root = nil,
  --- Files/dirs that mark a journal root when `root` is not set.
  root_markers = { ".llm-wiki-layout" },
  --- Paths relative to the root.
  dirs = {
    daily = "journal/daily",
    meetings = "journal/meetings",
    inbox = "journal/INBOX.md",
    done = "journal/DONE.md",
    journal_entries = "journal/journal-entries",
    done_entries = "journal/done-entries",
    templates = "journal/templates",
    reports = "journal/reports",
  },
  affixes = {
    daily = "daily-",
    week = "week-",
    done_week = "done-week-",
  },
  ---@type "wiki"|"markdown"
  link_style = "wiki",
  --- Directory (relative to root) that wiki-link targets are relative to.
  link_base = "journal",
  --- ISO weekday numbers (Mon = 1 … Sun = 7).
  workdays = { 1, 2, 3, 4, 5 },
  --- "auto" (snacks -> fzf_lua -> telescope -> select) or a backend name.
  picker = "auto",
  --- Meeting note types. Set a type to `false` to remove it.
  --- Fields: label, template, order, and either `title` (fixed, no prompt) or `prompt`
  --- (asks for input; `title` may then use `{input}`).
  meeting_types = {
    planning = { label = "Sprint planning", template = "planning", title = "Sprint planning", order = 10 },
    refinement = { label = "Refinement", template = "refinement", title = "Refinement", order = 20 },
    review = { label = "Sprint review", template = "review", title = "Sprint review", order = 30 },
    retro = { label = "Retrospective", template = "retro", title = "Retro", order = 40 },
    ["1on1"] = { label = "1:1", template = "1on1", prompt = "Person: ", title = "1:1 {input}", order = 50 },
    adhoc = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
  },
  --- Meeting filename (without .md). Variables: {date}, {time} (HHMM), {slug}, {type}.
  meeting_filename = "{date} - {slug}",
}

--- Keys whose values are open-ended tables (no unknown-key warnings inside).
M.open_keys = { meeting_types = true }

---@type logpose.Config?
M.options = nil

-- Non-empty array. `{}` is ambiguous, so it counts as a dict (an empty override keeps the base).
local function is_list(t)
  return type(t) == "table" and next(t) ~= nil and (vim.islist or vim.tbl_islist)(t)
end

--- Deep merge where lists are replaced, not merged index by index.
local function merge(base, override)
  if type(base) ~= "table" or type(override) ~= "table" or is_list(base) or is_list(override) then
    return vim.deepcopy(override)
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(override) do
    out[k] = merge(base[k], v)
  end
  return out
end

local function warn_unknown(defaults, opts, prefix, warnings)
  for k, v in pairs(opts) do
    local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
    local d = defaults[k]
    if d == nil and not (prefix == "" and k == "root") then
      table.insert(warnings, path)
    elseif type(d) == "table" and not is_list(d) and type(v) == "table" and not M.open_keys[path] then
      warn_unknown(d, v, path, warnings)
    end
  end
end

---@param opts table
local function validate(opts)
  local function check(name, value, expected, optional)
    if value == nil and optional then
      return
    end
    if type(value) ~= expected then
      error(("logpose: `%s` must be a %s, got %s"):format(name, expected, type(value)), 0)
    end
  end
  check("root", opts.root, "string", true)
  check("root_markers", opts.root_markers, "table")
  check("dirs", opts.dirs, "table")
  for k, v in pairs(opts.dirs) do
    check("dirs." .. k, v, "string")
  end
  check("affixes", opts.affixes, "table")
  for k, v in pairs(opts.affixes) do
    check("affixes." .. k, v, "string")
  end
  if opts.link_style ~= "wiki" and opts.link_style ~= "markdown" then
    error(('logpose: `link_style` must be "wiki" or "markdown", got %s'):format(vim.inspect(opts.link_style)), 0)
  end
  check("link_base", opts.link_base, "string")
  check("picker", opts.picker, "string")
  check("meeting_filename", opts.meeting_filename, "string")
  if not opts.meeting_filename:find("{slug}", 1, true) then
    error("logpose: `meeting_filename` must contain {slug}", 0)
  end
  check("meeting_types", opts.meeting_types, "table")
  for name, t in pairs(opts.meeting_types) do
    if t ~= false then
      check("meeting_types." .. name, t, "table")
      check("meeting_types." .. name .. ".template", t.template, "string", true)
      check("meeting_types." .. name .. ".label", t.label, "string", true)
      check("meeting_types." .. name .. ".title", t.title, "string", true)
      check("meeting_types." .. name .. ".prompt", t.prompt, "string", true)
      check("meeting_types." .. name .. ".order", t.order, "number", true)
    end
  end
  check("workdays", opts.workdays, "table")
  for _, w in ipairs(opts.workdays) do
    if type(w) ~= "number" or w < 1 or w > 7 or w % 1 ~= 0 then
      error(("logpose: `workdays` entries must be integers 1-7 (Mon=1), got %s"):format(vim.inspect(w)), 0)
    end
  end
end

--- Merge user options over the defaults. Raises on invalid values, warns on unknown keys.
---@param opts? table
---@return logpose.Config
function M.setup(opts)
  opts = opts or {}
  local warnings = {}
  warn_unknown(M.defaults, opts, "", warnings)
  local merged = merge(M.defaults, opts)
  validate(merged)
  M.options = merged
  if #warnings > 0 then
    table.sort(warnings)
    vim.notify("logpose: unknown option(s): " .. table.concat(warnings, ", "), vim.log.levels.WARN)
  end
  return merged
end

--- Current options (defaults if `setup()` was never called).
---@return logpose.Config
function M.get()
  if not M.options then
    M.options = vim.deepcopy(M.defaults)
  end
  return M.options
end

---@alias logpose.RootSource "config"|"buffer"|"cwd"

--- Resolve the journal root: configured `root` -> marker above the current buffer -> marker above cwd.
---@return string? root, logpose.RootSource|string source_or_err
function M.resolve_root()
  local opts = M.get()
  if opts.root then
    local root = fs.normalize(opts.root):gsub("/$", "")
    if not fs.is_dir(root) then
      return nil, ("logpose: configured root %s is not a directory"):format(opts.root)
    end
    return root, "config"
  end
  local markers = opts.root_markers
  if #markers > 0 then
    local name = vim.api.nvim_buf_get_name(0)
    -- Only real files: skip unnamed, special (help, terminal…) and URI buffers (health://, oil://…).
    if name ~= "" and vim.bo.buftype == "" and not name:match("^%a[%w+.-]*://") then
      local root = vim.fs.root(0, markers)
      if root then
        return root, "buffer"
      end
    end
    local root = vim.fs.root(vim.fn.getcwd(), markers)
    if root then
      return root, "cwd"
    end
  end
  return nil, "logpose: journal root not found; set `root` in setup()"
end

--- Resolve the root or raise a user-facing error.
---@return string
function M.root()
  local root, err = M.resolve_root()
  if not root then
    error(err, 0)
  end
  return root
end

--- Absolute path for a `dirs` entry.
---@param key string
---@param root? string
---@return string
function M.path(key, root)
  local rel = M.get().dirs[key]
  if not rel then
    error(("logpose: unknown dirs key %q"):format(key), 0)
  end
  return fs.join(root or M.root(), rel)
end

return M

--- Configuration: defaults, merging, validation and journal-root resolution.
local fs = require("logpose.util.fs")

local M = {}

---@class logpose.Config
M.defaults = {
  --- Absolute path to the journal repo (recommended). `~` is expanded.
  ---@type string?
  root = nil,
  --- Files/dirs that mark a journal root when `root` is not set.
  --- `:Logpose init` creates the first one.
  root_markers = { ".logpose" },
  --- Paths relative to the root.
  dirs = {
    daily = "daily",
    meetings = "meetings",
    templates = "templates",
    reports = "reports",
    notes = "notes",
    projects = "projects",
    tasks = "tasks",
  },
  affixes = {
    daily = "daily-",
    --- Prefixes of the folders done tasks are archived in, under tasks/archive/ (the week's start
    --- date or the sprint name follows: week-2026-10-12/, sprint-42/).
    week = "week-",
    sprint = "",
  },
  ---@type "wiki"|"markdown"
  link_style = "wiki",
  --- Directory (relative to root) that wiki-link targets are relative to ("" = the root).
  link_base = "",
  --- ISO weekday numbers (Mon = 1 … Sun = 7).
  workdays = { 1, 2, 3, 4, 5 },
  --- "auto" (snacks -> fzf_lua -> telescope -> select) or a backend name.
  picker = "auto",
  --- Meeting note types. Set a type to `false` to remove it.
  --- Fields: label, template, order, and either `title` (fixed, no prompt) or `prompt`
  --- (asks for input; `title` may then use `{input}`). `person = true`: the answer is a person.
  --- `ask_attendees = true`: also ask for attendees (comma separated, with completion).
  meeting_types = {
    planning = { label = "Sprint planning", template = "planning", title = "Sprint planning", order = 10 },
    refinement = { label = "Refinement", template = "refinement", title = "Refinement", order = 20 },
    review = { label = "Sprint review", template = "review", title = "Sprint review", order = 30 },
    retro = { label = "Retrospective", template = "retro", title = "Retro", order = 40 },
    ["1on1"] = {
      label = "1:1",
      template = "1on1",
      prompt = "Person: ",
      title = "1:1 {input}",
      person = true, -- the answer is a person: stored as `with:` and an attendee
      order = 50,
    },
    adhoc = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
  },
  --- Meeting filename (without .md). Variables: {date}, {time} (HHMM), {slug}, {type}.
  meeting_filename = "{date} - {slug}",
  --- Subdirectory of `dirs.meetings` for meeting notes. `{project}` is the active project
  --- (empty when there is none); "" keeps every note directly in `dirs.meetings`.
  meeting_subdir = "{project}",
  --- Weeks or sprints: reports, the standup, `today` and the task archive go by them.
  period = {
    ---@type "week"|"sprint"
    kind = "week",
    --- ISO weekday weeks start on (Mon = 1 … Sun = 7).
    week_start = 1,
    sprint = {
      --- Start date (YYYY-MM-DD) of any one sprint. Required for kind = "sprint"; also enables {sprint}.
      ---@type string?
      anchor = nil,
      length_days = 14,
      --- Number of the sprint that starts on `anchor`.
      first_number = 1,
      --- Sprint name; {n} is its number.
      name = "sprint-{n}",
    },
  },
  --- Your handle in action items, e.g. "@emmanuel" (used by `:Logpose actions mine`).
  ---@type string?
  me = nil,
  actions = {
    --- Also collect to-dos from daily notes (meetings only by default).
    include_daily = false,
    --- Items without an @owner count as yours for `mine`.
    unassigned_mine = true,
    ---@type "quickfix"|"picker"
    output = "quickfix",
  },
  series = {
    --- A new meeting in a series gets the previous one's open items under `## Carried over`.
    carry_over = true,
    --- Mark carried items in the previous note as `- [>]` so they aren't listed twice.
    mark_carried = true,
  },
  standup = {
    --- Daily-note section names.
    sections = { yesterday = "Yesterday", today = "Today", blockers = "Blockers" },
    --- A new daily note gets the previous one's open Today to-dos.
    carry_forward = true,
    --- ...and marks them `- [>]` in the previous note so they're tracked once.
    mark_carried = true,
    --- Group :Logpose standup items by project (#project tags).
    group_by_project = true,
  },
  review = {
    --- Open to-dos older than this many days, and tasks in progress longer, are flagged in reports.
    stale_days = 14,
  },
  tickets = {
    --- Lua pattern for ticket IDs (default: JIRA-style PROJ-123).
    pattern = "%u[%u%d]+%-%d+",
    --- URL template; {id} is the ticket. nil disables `gx` on tickets.
    ---@type string?
    url = nil,
  },
  telemetry = {
    --- Local usage counts (stdpath("data")/logpose/usage.json), on by default. Nothing leaves
    --- your machine; set to false to stop counting.
    enabled = true,
    retention_days = 180,
  },
  --- Saved searches: name -> `:Logpose find` arguments, run with `:Logpose view <name>`.
  views = {},
  tasks = {
    --- Column a captured task starts in, and one promoted from a to-do.
    capture_status = "backlog",
    promote_status = "todo",
  },
  board = {
    --- Columns, left to right. `key` is the task's `status:`; `label` is shown; optional `limit`
    --- (WIP limit: the count turns red above it) and `hl` (highlight group for the column).
    columns = {
      { key = "backlog", label = "Backlog" },
      { key = "todo", label = "TODO" },
      { key = "in-progress", label = "In progress", limit = 3 },
      { key = "follow-up", label = "Follow-up" },
      { key = "done", label = "Done" },
    },
    --- Reaching this column sets `started:`; reaching `done` sets `done:`.
    start = "in-progress",
    done = "done",
    --- Done tasks shown: "period" (current week or sprint) or a number of days.
    ---@type "period"|integer
    done_window = "period",
    --- Narrower than this, columns stack vertically.
    min_column_width = 24,
    --- Cards untouched for this many days in a column (not Done) are shown faded.
    stale_days = 7,
    --- Columns folded to a narrow strip when the board opens (`z` toggles), e.g. { "done" }.
    collapsed = {},
    --- Card borders: "column" (each card in its column's colour), "project" (tinted with the
    --- card's project colour) or "neutral" (one quiet colour).
    ---@type "column"|"project"|"neutral"
    border = "column",
    --- Glyphs: "unicode", "nerd" (needs a Nerd Font) or "ascii".
    ---@type "unicode"|"nerd"|"ascii"
    icons = "unicode",
    --- Start with one-line cards (`c` toggles) / rows per project (`s` toggles).
    compact = false,
    lanes = false,
    --- Where the board opens: "window" (the current one) or "tab" (its own tab page).
    ---@type "window"|"tab"
    open = "window",
  },
  --- `true` installs a `<leader>j…` keymap set (`{ prefix = "<leader>n" }` for another prefix);
  --- keys you've mapped yourself are never replaced.
  ---@type boolean|{ prefix?: string }
  keymaps = false,
  timestamps = {
    --- `created:` / `modified:` (local time, 2026-10-15T18:57) in the frontmatter of new notes.
    --- `modified:` is bumped when logpose rewrites a note and when you save a changed one.
    created = true,
    modified = true,
  },
  search = {
    --- Re-run the search as you edit the picker prompt (snacks, fzf-lua, telescope). The prompt
    --- takes the same filters as :Logpose find. false = the picker fuzzy-filters fixed results.
    live = true,
  },
  retrieval = {
    --- Every line under these `## ` headings is searchable (find decisions, section:…).
    sections = { "decisions", "blockers", "risks", "open questions" },
  },
  projects = {
    --- Use the git repo of the current buffer (or cwd) as the project.
    detect = true,
    --- Directory -> project name, e.g. { ["~/work/acme-api"] = "acme" }. Longest match wins.
    paths = {},
    --- Open the project's board when you switch to a project.
    open_board = true,
  },
}

--- Keys whose default is nil (so they're known even though absent from `defaults`).
M.optional_keys = { root = true, me = true, ["period.sprint.anchor"] = true, ["tickets.url"] = true }

--- Keys whose values are open-ended tables (no unknown-key warnings inside).
M.open_keys = { meeting_types = true, ["projects.paths"] = true, views = true }

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
    if d == nil and not M.optional_keys[path] then
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
  check("period", opts.period, "table")
  if opts.period.kind ~= "week" and opts.period.kind ~= "sprint" then
    error(('logpose: `period.kind` must be "week" or "sprint", got %s'):format(vim.inspect(opts.period.kind)), 0)
  end
  local ws = opts.period.week_start
  if type(ws) ~= "number" or ws < 1 or ws > 7 or ws % 1 ~= 0 then
    error(("logpose: `period.week_start` must be an integer 1-7 (Mon=1), got %s"):format(vim.inspect(ws)), 0)
  end
  local sprint = opts.period.sprint
  check("period.sprint", sprint, "table")
  if sprint.anchor ~= nil and not require("logpose.util.date").is_iso(sprint.anchor) then
    error(("logpose: `period.sprint.anchor` must be a YYYY-MM-DD date, got %s"):format(vim.inspect(sprint.anchor)), 0)
  end
  if opts.period.kind == "sprint" and sprint.anchor == nil then
    error('logpose: `period.sprint.anchor` is required when `period.kind = "sprint"`', 0)
  end
  local len = sprint.length_days
  if type(len) ~= "number" or len < 1 or len % 1 ~= 0 then
    error(("logpose: `period.sprint.length_days` must be a positive integer, got %s"):format(vim.inspect(len)), 0)
  end
  if type(sprint.first_number) ~= "number" or sprint.first_number % 1 ~= 0 then
    error("logpose: `period.sprint.first_number` must be an integer", 0)
  end
  check("period.sprint.name", sprint.name, "string")
  check("me", opts.me, "string", true)
  check("actions", opts.actions, "table")
  check("actions.include_daily", opts.actions.include_daily, "boolean")
  check("actions.unassigned_mine", opts.actions.unassigned_mine, "boolean")
  if opts.actions.output ~= "quickfix" and opts.actions.output ~= "picker" then
    error(
      ('logpose: `actions.output` must be "quickfix" or "picker", got %s'):format(vim.inspect(opts.actions.output)),
      0
    )
  end
  check("series", opts.series, "table")
  check("series.carry_over", opts.series.carry_over, "boolean")
  check("series.mark_carried", opts.series.mark_carried, "boolean")
  check("standup", opts.standup, "table")
  check("standup.sections", opts.standup.sections, "table")
  for _, k in ipairs({ "yesterday", "today", "blockers" }) do
    check("standup.sections." .. k, opts.standup.sections[k], "string")
  end
  for _, k in ipairs({ "carry_forward", "mark_carried", "group_by_project" }) do
    check("standup." .. k, opts.standup[k], "boolean")
  end
  check("review", opts.review, "table")
  check("review.stale_days", opts.review.stale_days, "number")
  check("tickets", opts.tickets, "table")
  check("tickets.pattern", opts.tickets.pattern, "string")
  check("tickets.url", opts.tickets.url, "string", true)
  check("telemetry", opts.telemetry, "table")
  check("telemetry.enabled", opts.telemetry.enabled, "boolean")
  check("telemetry.retention_days", opts.telemetry.retention_days, "number")
  check("views", opts.views, "table")
  for name, v in pairs(opts.views) do
    check("views." .. tostring(name), v, "string")
  end
  check("tasks", opts.tasks, "table")
  check("board", opts.board, "table")
  check("board.columns", opts.board.columns, "table")
  if #opts.board.columns < 2 then
    error("logpose: `board.columns` needs at least two columns", 0)
  end
  local keys = {}
  for i, col in ipairs(opts.board.columns) do
    check(("board.columns[%d]"):format(i), col, "table")
    check(("board.columns[%d].key"):format(i), col.key, "string")
    check(("board.columns[%d].label"):format(i), col.label, "string", true)
    check(("board.columns[%d].hl"):format(i), col.hl, "string", true)
    check(("board.columns[%d].limit"):format(i), col.limit, "number", true)
    if not col.key:match("^[%w_%-]+$") then
      error(("logpose: board column key %q may only use letters, digits, - and _"):format(col.key), 0)
    end
    if keys[col.key] then
      error(("logpose: duplicate board column %q"):format(col.key), 0)
    end
    keys[col.key] = true
  end
  for _, name in ipairs({ "board.start", "board.done", "tasks.capture_status", "tasks.promote_status" }) do
    local section, key = name:match("^(%w+)%.([%w_]+)$")
    local v = opts[section][key]
    check(name, v, "string")
    if not keys[v] then
      error(("logpose: `%s` = %q is not a board column"):format(name, v), 0)
    end
  end
  if opts.board.done_window ~= "period" and type(opts.board.done_window) ~= "number" then
    error('logpose: `board.done_window` must be "period" or a number of days', 0)
  end
  check("board.min_column_width", opts.board.min_column_width, "number")
  check("board.stale_days", opts.board.stale_days, "number")
  check("board.collapsed", opts.board.collapsed, "table")
  if not vim.tbl_contains({ "project", "neutral", "column" }, opts.board.border) then
    error('logpose: `board.border` must be "project", "neutral" or "column"', 0)
  end
  if not vim.tbl_contains({ "unicode", "nerd", "ascii" }, opts.board.icons) then
    error('logpose: `board.icons` must be "unicode", "nerd" or "ascii"', 0)
  end
  check("board.compact", opts.board.compact, "boolean")
  check("board.lanes", opts.board.lanes, "boolean")
  if opts.board.open ~= "window" and opts.board.open ~= "tab" then
    error('logpose: `board.open` must be "window" or "tab"', 0)
  end
  if type(opts.keymaps) ~= "boolean" and type(opts.keymaps) ~= "table" then
    error("logpose: `keymaps` must be true, false or { prefix = ... }", 0)
  end
  check("timestamps", opts.timestamps, "table")
  check("timestamps.created", opts.timestamps.created, "boolean")
  check("timestamps.modified", opts.timestamps.modified, "boolean")
  check("search", opts.search, "table")
  check("search.live", opts.search.live, "boolean")
  check("retrieval", opts.retrieval, "table")
  check("retrieval.sections", opts.retrieval.sections, "table")
  check("meeting_subdir", opts.meeting_subdir, "string")
  check("projects", opts.projects, "table")
  check("projects.detect", opts.projects.detect, "boolean")
  check("projects.paths", opts.projects.paths, "table")
  check("projects.open_board", opts.projects.open_board, "boolean")
  for dir, name in pairs(opts.projects.paths) do
    check("projects.paths key", dir, "string")
    check(("projects.paths[%q]"):format(tostring(dir)), name, "string")
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
      check("meeting_types." .. name .. ".person", t.person, "boolean", true)
      check("meeting_types." .. name .. ".ask_attendees", t.ask_attendees, "boolean", true)
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
    require("logpose.util.ui").notify(
      "logpose: unknown option(s): " .. table.concat(warnings, ", "),
      vim.log.levels.WARN
    )
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

---@alias logpose.RootSource "config"|"buffer"|"cwd"|"saved"

M.NOT_FOUND = "logpose: journal root not found; run :Logpose init or set `root` in setup()"

--- Resolve the journal root: configured `root` -> marker above the current buffer ->
--- marker above cwd -> the root saved by `:Logpose init`.
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
  local saved = require("logpose.state").get("root")
  if type(saved) == "string" and fs.is_dir(saved) then
    return saved, "saved"
  end
  return nil, M.NOT_FOUND
end

--- Run `fn(root)` with the journal root. When there is none, offer to create one
--- (`:Logpose init` flow) and continue with it.
---@param fn fun(root: string)
function M.with_root(fn)
  local root = M.resolve_root()
  if root then
    fn(root)
    return
  end
  if M.get().root then
    error(select(2, M.resolve_root()), 0) -- a configured but missing root is a config error
  end
  require("logpose.onboard").prompt({ first_run = true }, fn)
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

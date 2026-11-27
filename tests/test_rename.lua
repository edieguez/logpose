local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(
        ("require('logpose').setup({ root = %q, picker = 'select', timestamps = { created = false, modified = false } })"):format(
          root
        )
      )
      H.freeze(child, 2026, 10, 20)
      H.write(root .. "/notes/queue.md", '---\ntitle: "Queue"\n---\nHow the queue works.\n')
      -- links to it: wiki, short wiki, markdown
      H.write(
        root .. "/notes/other.md",
        '---\ntitle: "Other"\n---\nSee [[notes/queue|the queue]], [[queue]] and [Queue](queue.md).\n'
      )
    end,
    post_once = child.stop,
  },
})

--- vim.ui.select picks the item whose label contains `want` (nil: cancels), and remembers what
--- it was offered.
local function select(want)
  child.lua(([[
    _G.offered = nil
    vim.ui.select = function(items, opts, cb)
      local labels = vim.tbl_map(opts.format_item or tostring, items)
      _G.offered = { prompt = opts.prompt, labels = labels }
      for i, l in ipairs(labels) do
        if %s and l:find(%s, 1, true) then return cb(items[i]) end
      end
      cb(nil)
    end
  ]]):format(want and "true" or "false", vim.inspect(want or "")))
end

local function input(answer)
  child.lua(("vim.ui.input = function(o, cb) _G.input_default = o.default; cb(%s) end"):format(vim.inspect(answer)))
end

--- Set a field in the open edit form.
local function set(key, value)
  local rows = child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      if m[4].virt_text_pos == "inline" then
        out[vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, m[4].virt_text)))] = m[2]
      end
    end
    return out
  end)()]])
  child.api.nvim_buf_set_lines(0, rows[key], rows[key] + 1, false, { value })
  child.lua("require('logpose.edit.form').render(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])")
end

local function below()
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      for _, vl in ipairs(m[4].virt_lines or {}) do
        table.insert(out, vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, vl))))
      end
    end
    return table.concat(out, "\n")
  end)()]])
end

local function exists(rel)
  return vim.fn.filereadable(root .. "/" .. rel) == 1
end

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

T["the form: a new title asks whether the file follows; yes renames it and fixes the links"] = function()
  child.cmd("edit " .. root .. "/notes/queue.md")
  child.cmd("Logpose edit")
  set("title", "Queue design v2")
  H.contains(below(), "then ask to rename the file to notes/queue-design-v2.md")
  select("Rename the file")
  child.cmd("write")
  eq(child.lua_get("_G.offered.labels"), { "Rename the file to notes/queue-design-v2.md", "Keep the file name" })
  H.contains(child.lua_get("_G.offered.prompt"), "“Queue design v2” has a new title: rename queue.md too?")
  eq(exists("notes/queue.md"), false)
  H.contains(H.read(root .. "/notes/queue-design-v2.md"), 'title: "Queue design v2"')
  eq(
    H.read(root .. "/notes/other.md"),
    '---\ntitle: "Other"\n---\n'
      .. "See [[notes/queue-design-v2|the queue]], [[queue-design-v2]] and [Queue](queue-design-v2.md).\n"
  )
  H.contains(last_msg(), "renamed to notes/queue-design-v2.md, fixing links in 1 note")
  -- the form edits it where it is now, and the note's buffer followed it
  eq(child.api.nvim_buf_get_name(0), "logpose://edit/queue-design-v2.md")
  child.type_keys("q")
  eq(child.api.nvim_buf_get_name(0), root .. "/notes/queue-design-v2.md")
end

T["the form: keeping the file name leaves the file and links alone"] = function()
  child.cmd("edit " .. root .. "/notes/queue.md")
  child.cmd("Logpose edit")
  set("title", "Queue design")
  select("Keep")
  child.cmd("write")
  H.contains(H.read(root .. "/notes/queue.md"), 'title: "Queue design"')
  eq(exists("notes/queue-design.md"), false)
  H.contains(H.read(root .. "/notes/other.md"), "[[notes/queue|the queue]]")
end

T["the form: a title with the same file name, or another field, asks nothing"] = function()
  child.cmd("edit " .. root .. "/notes/queue.md")
  child.cmd("Logpose edit")
  set("title", "QUEUE")
  eq(below():find("rename the file", 1, true), nil)
  select("Rename")
  child.cmd("write")
  eq(child.lua_get("_G.offered"), vim.NIL)
  set("tags", "infra")
  child.cmd("write")
  eq(child.lua_get("_G.offered"), vim.NIL)
end

T["a name that's taken gets -2"] = function()
  H.write(root .. "/notes/design.md", '---\ntitle: "Design"\n---\n')
  child.cmd("edit " .. root .. "/notes/queue.md")
  child.cmd("Logpose rename Design")
  eq(exists("notes/design-2.md"), true)
  eq(H.read(root .. "/notes/design.md"), '---\ntitle: "Design"\n---\n') -- untouched
end

T[":Logpose rename asks for the title, starting from the current one"] = function()
  child.cmd("edit " .. root .. "/notes/queue.md")
  input("Message queue")
  child.cmd("Logpose rename")
  eq(child.lua_get("_G.input_default"), "Queue")
  eq(exists("notes/message-queue.md"), true)
  eq(child.api.nvim_buf_get_name(0), root .. "/notes/message-queue.md")
  -- the same file name: only the title changes
  child.cmd("Logpose rename message QUEUE")
  H.contains(H.read(root .. "/notes/message-queue.md"), 'title: "message QUEUE"')
  H.contains(last_msg(), "the file name stays")
end

T[":Logpose rename refuses tasks, daily notes and project pages, and unsaved notes"] = function()
  H.write(root .. "/tasks/fix.md", '---\ntitle: "Fix"\nstatus: todo\n---\n')
  child.cmd("edit " .. root .. "/tasks/fix.md")
  child.cmd("Logpose rename Fix it")
  H.contains(last_msg(), "a task keeps its file name")
  eq(exists("tasks/fix.md"), true)
  H.write(root .. "/daily/daily-2026-10-20.md", "# d\n")
  child.cmd("edit " .. root .. "/daily/daily-2026-10-20.md")
  child.cmd("Logpose rename Monday")
  H.contains(last_msg(), "named by its date")
  H.write(root .. "/projects/acme.md", '---\ntitle: "Acme"\nproject: acme\n---\n')
  child.cmd("edit " .. root .. "/projects/acme.md")
  child.cmd("Logpose rename Acme API")
  H.contains(last_msg(), "rename the project with R")
  child.cmd("edit " .. root .. "/notes/queue.md")
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "more" })
  child.cmd("Logpose rename New")
  H.contains(last_msg(), "save the note first")
  eq(exists("notes/queue.md"), true)
end

--- Three meetings of an ad-hoc series, linked previous/next.
local function sync_series()
  local dir = root .. "/meetings/acme/"
  local function note(d, prev, nxt)
    local lines = { "---", "type: adhoc", "date: " .. d, "project: acme", 'title: "Sync"', "series: acme/adhoc-sync" }
    if prev then
      table.insert(lines, ('previous: "[[meetings/acme/%s 0900 - sync|Sync %s]]"'):format(prev, prev))
    end
    if nxt then
      table.insert(lines, ('next: "[[meetings/acme/%s 0900 - sync|Sync %s]]"'):format(nxt, nxt))
    end
    vim.list_extend(lines, { "---", "## Notes", "" })
    H.write(dir .. d .. " 0900 - sync.md", table.concat(lines, "\n"))
  end
  note("2026-10-01", nil, "2026-10-08")
  note("2026-10-08", "2026-10-01", "2026-10-15")
  note("2026-10-15", "2026-10-08", nil)
  child.lua(
    "require('logpose').setup(vim.tbl_extend('force', require('logpose.config').get(), { meeting_filename = '{date} {time} - {slug}' }))"
  )
end

T["an ad-hoc meeting keeps its date and time, and starts a series of its own"] = function()
  sync_series()
  child.cmd("edit " .. vim.fn.fnameescape(root .. "/meetings/acme/2026-10-08 0900 - sync.md"))
  child.cmd("Logpose rename Design sync")
  local moved = root .. "/meetings/acme/2026-10-08 0900 - design-sync.md"
  local text = H.read(moved)
  H.contains(text, 'title: "Design sync"\nseries: acme/adhoc-design-sync\n')
  eq(text:find("previous:", 1, true), nil) -- alone in its series
  eq(text:find("next:", 1, true), nil)
  -- the old series closes the gap
  H.contains(
    H.read(root .. "/meetings/acme/2026-10-01 0900 - sync.md"),
    'next: "[[meetings/acme/2026-10-15 0900 - sync|'
  )
  H.contains(
    H.read(root .. "/meetings/acme/2026-10-15 0900 - sync.md"),
    'previous: "[[meetings/acme/2026-10-01 0900 - sync|'
  )
end

T["a retro keeps its series: the type is the series, not the title"] = function()
  H.write(
    root .. "/meetings/2026-10-08 - retro.md",
    '---\ntype: retro\ndate: 2026-10-08\ntitle: "Retro"\nseries: retro\n---\n'
  )
  child.cmd("edit " .. vim.fn.fnameescape(root .. "/meetings/2026-10-08 - retro.md"))
  child.cmd("Logpose rename Retro Q4")
  H.contains(H.read(root .. "/meetings/2026-10-08 - retro-q4.md"), "series: retro\n")
end

T["R on the notes list and the meetings list renames the note under the cursor"] = function()
  child.cmd("Logpose notes")
  local function on(s)
    for i, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find(s, 1, true) then
        child.api.nvim_win_set_cursor(0, { i, 0 })
        return
      end
    end
    error("no row with " .. s)
  end
  on("Queue")
  input("Queue design")
  child.type_keys("R")
  eq(exists("notes/queue-design.md"), true)
  H.contains(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "Queue design")
  sync_series()
  child.cmd("Logpose meetings")
  on("Sync")
  input("Weekly sync")
  child.type_keys("R")
  eq(#vim.fn.glob(root .. "/meetings/acme/*weekly-sync.md", true, true), 1)
end

T["a person's new name in the form: their page moves and the journal follows, as rename-person"] = function()
  H.write(root .. "/people/ana.md", '---\nname: "Ana"\n---\n')
  H.write(root .. "/notes/team.md", '---\ntitle: "Team"\n---\nAsk @ana.\n')
  child.cmd("edit " .. root .. "/people/ana.md")
  child.cmd("Logpose edit")
  set("name", "Ana López")
  select("Rename the file")
  child.cmd("write")
  eq(exists("people/ana.md"), false)
  local page = H.read(root .. "/people/ana-lopez.md")
  H.contains(page, "name: Ana López\n")
  H.contains(page, "aliases: [Ana]")
  H.contains(H.read(root .. "/notes/team.md"), "Ask @ana-lopez.")
end

return T

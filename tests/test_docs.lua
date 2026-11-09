local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir()) -- no project here
      child.o.columns, child.o.lines = 140, 50
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 11, 9)
      H.write(root .. "/projects/acme.md", '---\ntitle: "Acme API"\ntype: project\nproject: acme\n---\n## Overview\n')
    end,
    post_once = child.stop,
  },
})

--- The form's rows: label → { value, eol }, and the lines below it.
local function drawn()
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
    local rows, below = {}, {}
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local row, d = m[2] + 1, m[4]
      rows[row] = rows[row] or { label = "", eol = "", value = lines[row] }
      local text = table.concat(vim.tbl_map(function(c) return c[1] end, d.virt_text or {}))
      if d.virt_text_pos == "inline" then
        rows[row].label = vim.trim(text)
      elseif d.virt_text_pos == "eol" then
        rows[row].eol = vim.trim(text)
      end
      for _, vl in ipairs(d.virt_lines or {}) do
        local l = vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, vl)))
        if l ~= "" then
          table.insert(below, l)
        end
      end
    end
    local by = {}
    for _, r in pairs(rows) do
      by[r.label] = r
    end
    return { rows = by, below = below }
  end)()]])
end

local function set(key, value)
  for row, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local _ = l
    local label = child.lua_get(([[(function()
      local ns = vim.api.nvim_get_namespaces()["logpose.edit"]
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, { %d, 0 }, { %d, -1 }, { details = true })) do
        if m[4].virt_text_pos == "inline" then
          return vim.trim(table.concat(vim.tbl_map(function(c) return c[1] end, m[4].virt_text)))
        end
      end
      return ""
    end)()]]):format(row - 1, row - 1))
    if label == key then
      child.api.nvim_buf_set_lines(0, row - 1, row, false, { value })
      child.lua(
        "require('logpose.edit.form').render(require('logpose.edit.form').forms[vim.api.nvim_get_current_buf()])"
      )
      return
    end
  end
  error("no field " .. key)
end

local function save()
  child.cmd("stopinsert")
  child.type_keys("<C-s>")
end

local function last_msg()
  local n = child.notifications()
  return n[#n] and n[#n].msg or ""
end

T[":Logpose doc opens the form; saving creates the doc in the project's folder"] = function()
  child.cmd("Logpose doc")
  eq(child.bo.filetype, "logpose-edit")
  eq(child.api.nvim_win_get_config(0).title[1][1], " New project doc ")
  local d = drawn()
  eq(d.rows.type.value, "decision") -- the first type
  H.contains(d.rows.project.eol, "a doc lives in a project's folder") -- no project yet
  set("title", "Use Postgres")
  set("project", "acme")
  d = drawn()
  eq(d.rows.project.eol:find("lives in", 1, true), nil)
  H.contains(d.rows.status.eol, "empty: proposed")
  eq(d.below[1], "saving will:")
  H.contains(table.concat(d.below, "\n"), "create projects/acme/use-postgres.md, a decision of acme")
  set("tags", "db")
  save()
  local path = root .. "/projects/acme/use-postgres.md"
  eq(child.api.nvim_buf_get_name(0), path)
  local text = H.read(path)
  H.contains(text, '---\ntitle: "Use Postgres"\ntype: decision\nproject: acme\nstatus: proposed\ntags: [db]\n')
  H.contains(text, "## Context\n\n## Decision")
  eq(child.api.nvim_get_current_line(), "") -- writing the context
  eq(child.api.nvim_buf_get_lines(0, child.fn.line(".") - 2, child.fn.line(".") - 1, false)[1], "## Context")
  H.contains(last_msg(), "created projects/acme/use-postgres.md")
end

T["the type and status are checked; a type without statuses takes none"] = function()
  child.cmd("Logpose doc runbook Deploy")
  local d = drawn()
  eq(d.rows.type.value, "runbook")
  eq(d.rows.title.value, "Deploy")
  set("type", "memo")
  H.contains(drawn().rows.type.eol, "not a doc type")
  set("type", "decision")
  set("status", "maybe")
  H.contains(drawn().rows.status.eol, "proposed, accepted, superseded, rejected")
  set("status", "accepted")
  set("project", "acme")
  save()
  H.contains(H.read(root .. "/projects/acme/deploy.md"), "status: accepted")
  -- a runbook has no status
  child.cmd("Logpose doc runbook Restore")
  set("project", "acme")
  save()
  local text = H.read(root .. "/projects/acme/restore.md")
  eq(text:find("status:", 1, true), nil)
  H.contains(text, "## Steps")
end

T["the index knows docs: their project from the folder, pages stay pages"] = function()
  H.write(root .. "/projects/acme/notes-on-auth.md", "# Notes on auth\n")
  H.write(
    root .. "/projects/acme/use-postgres.md",
    '---\ntitle: "Use Postgres"\ntype: decision\nstatus: accepted\n---\n'
  )
  local got = child.lua_get(([[(function()
    local out = {}
    for _, it in ipairs(require("logpose.index").build(%q)) do
      if it.kind == "note" then
        out[vim.fs.basename(it.file)] = { it.file_type, it.project or false, it.type or false }
      end
    end
    return out
  end)()]]):format(root))
  eq(got["acme.md"], { "project", "acme", "project" })
  eq(got["notes-on-auth.md"], { "doc", "acme", false })
  eq(got["use-postgres.md"], { "doc", "acme", "decision" })
  -- filters find them
  local found = child.lua_get(
    ([[vim.tbl_map(function(it) return vim.fs.basename(it.file) end,
    require("logpose.query").filter(require("logpose.index").build(%q), require("logpose.query").parse({ "type:decision" })))]]):format(
      root
    )
  )
  eq(found, { "use-postgres.md" })
end

T["another project moves the doc to its folder; links follow"] = function()
  H.write(root .. "/projects/acme/use-postgres.md", '---\ntitle: "Use Postgres"\ntype: decision\nproject: acme\n---\n')
  H.write(root .. "/notes/db.md", "# DB\nsee [[projects/acme/use-postgres|the decision]]\n")
  child.cmd("edit " .. root .. "/projects/acme/use-postgres.md")
  child.cmd("Logpose edit")
  set("project", "billing")
  H.contains(table.concat(drawn().below, "\n"), "move the doc to projects/billing/, fixing 1 link to it")
  save()
  local moved = root .. "/projects/billing/use-postgres.md"
  eq(vim.fn.filereadable(moved), 1)
  eq(vim.fn.isdirectory(root .. "/projects/acme"), 0) -- emptied, so gone
  H.contains(H.read(moved), "project: billing")
  H.contains(H.read(root .. "/notes/db.md"), "[[projects/billing/use-postgres|the decision]]")
  -- no project: refused
  set("project", "")
  H.contains(drawn().rows.project.eol, "a doc lives in a project's folder")
end

T["the notes list groups docs by type; a adds one, m moves it"] = function()
  H.write(
    root .. "/projects/acme/use-postgres.md",
    '---\ntitle: "Use Postgres"\ntype: decision\nproject: acme\nstatus: accepted\n---\n'
  )
  H.write(root .. "/projects/acme/deploy.md", '---\ntitle: "Deploy"\ntype: runbook\nproject: acme\n---\n')
  H.write(root .. "/notes/queue.md", '---\ntitle: "Queue design"\n---\n')
  child.cmd("Logpose notes")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  local function at(s)
    for i, l in ipairs(lines) do
      if l:find(s, 1, true) then
        return i
      end
    end
  end
  assert(at("Topic notes") < at("Decisions"), "topic notes first")
  assert(at("Decisions") < at("Runbooks"), "decisions, then runbooks")
  assert(at("Runbooks") < at("Project pages"), "then the project pages")
  H.contains(text, "accepted") -- a decision's status
  -- a under Decisions: a new decision
  child.api.nvim_win_set_cursor(0, { at("Use Postgres"), 2 })
  child.type_keys("a")
  eq(child.bo.filetype, "logpose-edit")
  eq(drawn().rows.type.value, "decision")
  child.type_keys("<Esc>", "q")
  -- grouped by project, m moves it to another project's folder
  child.type_keys("g")
  child.api.nvim_win_set_cursor(0, { child.fn.search("Deploy", "n"), 2 })
  child.lua([[vim.ui.input = function(_, cb) cb("billing") end
    vim.ui.select = function(items, _, cb)
      for _, it in ipairs(items) do
        if (it.label or it) == "new…" or (it.key == nil and tostring(it.label):find("new")) then return cb(it) end
      end
      cb(items[#items])
    end]])
  child.type_keys("m")
  eq(vim.fn.filereadable(root .. "/projects/billing/deploy.md"), 1)
end

T["rename-project moves the folder of docs; merge-project moves what's in it"] = function()
  H.write(root .. "/projects/acme/use-postgres.md", '---\ntitle: "Use Postgres"\ntype: decision\nproject: acme\n---\n')
  H.write(root .. "/projects/acme/img/diagram.txt", "a diagram\n")
  H.write(root .. "/notes/db.md", "# DB\n[[projects/acme/use-postgres]] and [[projects/acme]]\n")
  child.cmd("Logpose rename-project! acme web")
  eq(vim.fn.isdirectory(root .. "/projects/acme"), 0)
  eq(vim.fn.filereadable(root .. "/projects/web/img/diagram.txt"), 1)
  H.contains(H.read(root .. "/projects/web/use-postgres.md"), "project: web")
  H.contains(H.read(root .. "/notes/db.md"), "[[projects/web/use-postgres]] and [[projects/web]]")
  -- merged into a project with docs of its own
  H.write(root .. "/projects/billing.md", '---\ntitle: "Billing"\ntype: project\nproject: billing\n---\n')
  H.write(root .. "/projects/billing/invoices.md", '---\ntitle: "Invoices"\ntype: spec\nproject: billing\n---\n')
  child.cmd("Logpose merge-project! web billing")
  eq(vim.fn.filereadable(root .. "/projects/billing/use-postgres.md"), 1)
  eq(vim.fn.filereadable(root .. "/projects/billing/img/diagram.txt"), 1)
  eq(vim.fn.isdirectory(root .. "/projects/web"), 0)
  H.contains(H.read(root .. "/projects/billing/use-postgres.md"), "project: billing")
  H.contains(H.read(root .. "/notes/db.md"), "[[projects/billing/use-postgres]]")
end

return T

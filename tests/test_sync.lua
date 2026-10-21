local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root, retro, task

local function write_task(status, log)
  H.write(
    task,
    ('---\ntitle: "Fix CI"\nstatus: %s\ncreated: 2026-10-10\n---\nFrom: [[meetings/2026-10-13 - retro|Retro]]\n%s'):format(
      status,
      log and ("\n## Log\n" .. log .. "\n") or ""
    )
  )
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      child.cmd("cd " .. H.tmpdir())
      child.lua(("require('logpose').setup({ root = %q, picker = 'select' })"):format(root))
      H.freeze(child, 2026, 10, 14, 10, 30)
      retro = root .. "/meetings/2026-10-13 - retro.md"
      task = root .. "/tasks/fix-ci.md"
      H.write(
        retro,
        '---\ntype: retro\ndate: 2026-10-13\ntitle: "Retro"\nmodified: 2026-10-13T09:00\n---\n## Action items\n\n- [ ] fix CI @ana\n  → [[tasks/fix-ci|task]]\n- [ ] other thing\n'
      )
      write_task("in-progress", "- 2026-10-12 09:00: TODO → In progress")
    end,
    post_once = child.stop,
  },
})

local function status()
  return H.read(task):match("\nstatus: (%S+)")
end

local function todo_line()
  return vim.split(H.read(retro), "\n")[9]
end

local function answer(choice)
  child.lua(([[vim.ui.select = function(items, opts, cb)
    _G.asked = opts.prompt
    for _, it in ipairs(items) do if it:find(%q, 1, true) then return cb(it) end end
    cb(nil)
  end]]):format(choice))
end

T["the task done checks its to-do; reopened, unchecks it"] = function()
  child.cmd("edit " .. task)
  child.cmd("Logpose done")
  eq(todo_line(), "- [x] fix CI @ana")
  H.contains(H.read(retro), "modified: 2026-10-13T09:00") -- left as it was
  H.contains(
    table.concat(
      vim.tbl_map(function(n)
        return n.msg
      end, child.notifications()),
      "\n"
    ),
    "checked its to-do in Retro"
  )
  child.lua("require('logpose.taskfile').set_status(..., 'in-progress')", { task })
  eq(todo_line(), "- [ ] fix CI @ana")
end

T["on the board: x checks the to-do, u unchecks it again"] = function()
  child.cmd("Logpose board")
  child.type_keys("ll") -- In progress
  child.type_keys("x")
  eq(status(), "done")
  eq(todo_line(), "- [x] fix CI @ana")
  child.type_keys("u")
  eq(status(), "in-progress")
  eq(todo_line(), "- [ ] fix CI @ana")
  child.type_keys("<C-r>")
  eq(todo_line(), "- [x] fix CI @ana")
end

T["checking the to-do moves a started task to Done; unchecking puts it back where it was"] = function()
  write_task("follow-up", "- 2026-10-12 09:00: TODO → In progress\n- 2026-10-13 09:00: In progress → Follow-up")
  child.cmd("edit " .. vim.fn.fnameescape(retro))
  child.api.nvim_win_set_cursor(0, { 9, 0 })
  child.cmd("Logpose check")
  eq(status(), "done")
  child.cmd("Logpose check")
  eq(status(), "follow-up")
  H.contains(H.read(task), "Done → Follow-up")
end

T["checking the to-do of a task that hasn't started asks first"] = function()
  write_task("todo")
  answer("Leave it")
  child.cmd("edit " .. vim.fn.fnameescape(retro))
  child.api.nvim_win_set_cursor(0, { 9, 0 })
  child.cmd("Logpose check")
  H.contains(child.lua_get("_G.asked"), '"Fix CI" hasn\'t started (TODO)')
  eq(status(), "todo")
  -- saving doesn't ask again
  child.lua("_G.asked = nil")
  child.cmd("write")
  child.lua("vim.wait(50)")
  eq(child.lua_get("_G.asked"), vim.NIL)
  -- unchecked and checked again, the answer is yes this time
  child.cmd("Logpose check")
  answer("Move it")
  write_task("backlog")
  child.lua("require('logpose.sync').declined = {}")
  child.cmd("Logpose check")
  eq(status(), "done")
end

T["boxes and statuses changed by hand follow when saved"] = function()
  child.cmd("edit " .. vim.fn.fnameescape(retro))
  child.api.nvim_buf_set_lines(0, 8, 9, false, { "- [x] fix CI @ana" })
  child.cmd("write")
  child.lua("vim.wait(50)")
  eq(status(), "done")
  -- the task file, by hand
  child.cmd("edit " .. task)
  child.cmd([[%s/^status: done/status: in-progress/]])
  child.cmd("write")
  child.lua("vim.wait(50)")
  eq(todo_line(), "- [ ] fix CI @ana")
end

T["a note with unsaved changes is edited in its buffer"] = function()
  child.cmd("edit " .. vim.fn.fnameescape(retro))
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "- typing" })
  child.cmd("enew")
  child.lua("require('logpose.taskfile').set_status(..., 'done')", { task })
  eq(todo_line(), "- [ ] fix CI @ana") -- the file is untouched
  local buf = child.fn.bufnr(retro)
  eq(child.api.nvim_buf_get_lines(buf, 8, 9, false)[1], "- [x] fix CI @ana")
  eq(child.api.nvim_buf_get_lines(buf, -2, -1, false)[1], "- typing")
end

T["a task done outside Neovim counts its to-do as done"] = function()
  write_task("done")
  local todo = child.lua_get(([[vim.tbl_filter(function(it)
    return it.kind == "todo" and it.text == "fix CI @ana"
  end, require("logpose.index").build(%q))[1] ]]):format(root))
  eq(todo.checked, true)
  eq(vim.fs.basename(todo.done_by_task), "fix-ci.md")
  child.cmd("Logpose actions")
  local qf = child.fn.getqflist()
  eq(#qf, 1) -- not an open action item any more; the other one is
  H.contains(qf[1].text, "other thing")
end

T["carried to-dos keep their task"] = function()
  local lines = child.lua_get(
    "require('logpose.standup').prefill({ '## Today', '- [ ] fix CI', '  → [[tasks/fix-ci|task]]', '- [x] done', '  → [[tasks/x|task]]' }).today"
  )
  eq(lines, { "- [ ] fix CI", "  → [[tasks/fix-ci|task]]" })
  -- a meeting series carries the open to-do with its task line; the new copy is linked
  local series = child.lua_get(
    ([[require("logpose.notes.meeting").series_lines(%q, %s, %s, %q)]]):format(
      root .. "/meetings/2026-10-20 - retro.md",
      vim.inspect({ file = retro, title = "Retro", date = "2026-10-13" }),
      vim.inspect({ { text = "fix CI @ana", task_link_text = "→ [[tasks/fix-ci|task]]" } }),
      root
    )
  )
  eq(
    vim.list_slice(series, #series - 1),
    { "- [ ] fix CI @ana (from [[meetings/2026-10-13 - retro|2026-10-13]])", "  → [[tasks/fix-ci|task]]" }
  )
end

return T

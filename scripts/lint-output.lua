-- Generate a journal with every template and every edit logpose makes, for markdownlint.
-- Usage: nvim --headless --clean -u scripts/lint-output.lua -- <empty dir>
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo)
local root = assert(vim.v.argv[#vim.v.argv], "journal dir")
vim.fn.mkdir(root, "p")
local function write(rel, text)
  local path = root .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end
local date = require("logpose.util.date")
local function at(y, m, d, h)
  date._now = function()
    return os.time({ year = y, month = m, day = d, hour = h or 10, min = 0 })
  end
end
vim.notify = function() end
vim.ui.select = function(items, _, cb)
  cb(items[1])
end
local answers = {}
vim.ui.input = function(_, cb)
  cb(table.remove(answers, 1) or "x")
end
write(".logpose", "")
require("logpose").setup({ root = root, projects = { paths = { [vim.fn.getcwd()] = "acme" } } })
vim.cmd("runtime plugin/logpose.lua")
local function run(cmd)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    io.stderr:write(cmd .. ": " .. tostring(err) .. "\n")
  end
end

-- Day 1: daily, every meeting type, topic note, project page, tasks.
at(2026, 10, 13)
run("Logpose daily")
vim.api.nvim_buf_set_lines(0, -1, -1, false, {})
run("silent! write")
for _, t in ipairs({ "planning", "refinement", "review", "retro" }) do
  run("Logpose meeting " .. t)
  -- an open action item to carry over
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:match("^## Action items") or l:match("^## Follow%-ups") then
      vim.api.nvim_buf_set_lines(buf, i, i, false, { "", "- [ ] follow up @ana due:2026-10-20" })
      break
    end
  end
  run("silent write")
end
answers = { "Ana" }
run("Logpose meeting 1on1")
answers = { "Sync with QA" }
run("Logpose meeting adhoc")
run("Logpose note Queue design")
run("Logpose project-page acme")
local ok_person, perr = pcall(require("logpose.people").create, root, {
  name = "Ana López",
  aliases = { "Ana" },
  role = "Backend lead",
  projects = { "acme" },
  email = "ana@acme.io",
})
if not ok_person then
  io.stderr:write("people.create: " .. tostring(perr) .. "\n")
end
run("Logpose capture fix flaky test #perf due:2026-10-20")
run("Logpose capture write the retro")
run("Logpose board")
vim.api.nvim_feedkeys("LL", "x", false)
answers = { "waiting on ana" }
vim.api.nvim_feedkeys("b", "x", false)
run("Logpose daily")
-- Day 2: carried to-dos, series, promote, done, the standup.
at(2026, 10, 14)
local d1 = root .. "/daily/daily-2026-10-13.md"
local l1 = vim.fn.readfile(d1)
for i, l in ipairs(l1) do
  if l == "## Notes" then
    table.insert(l1, i + 1, "")
    table.insert(l1, i + 2, "- [x] shipped it #acme")
    table.insert(l1, i + 3, "- [ ] keep going #acme")
    break
  end
end
vim.fn.writefile(l1, d1)
run("Logpose daily")
run("Logpose meeting retro")
local buf = vim.api.nvim_get_current_buf()
for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if l:match("^%- %[ %] follow up") then
    vim.api.nvim_win_set_cursor(0, { i, 0 })
    run("Logpose promote")
    break
  end
end
run("edit " .. root .. "/tasks/write-the-retro.md")
run("Logpose done")
-- Inbox mode: capture, done, migrate, archive.
require("logpose").setup({ root = root, tasks = { mode = "inbox" } })
at(2026, 10, 6)
run("Logpose capture old item #acme")
at(2026, 10, 14)
run("Logpose capture new item #acme")
run("Logpose capture another one")
run("edit " .. root .. "/INBOX.md")
for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if l:match("new item") then
    vim.api.nvim_win_set_cursor(0, { i, 0 })
    run("Logpose done")
    break
  end
end
require("logpose").setup({ root = root })
at(2026, 10, 21)
run("Logpose migrate!")
run("Logpose archive!")
run("Logpose report! week -1")
run("Logpose report! week")
vim.cmd("qa!")

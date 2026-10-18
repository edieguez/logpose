local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local root, work

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      root = H.journal()
      work = H.tmpdir()
      child.cmd("cd " .. work)
      child.lua(("require('logpose').setup({ root = %q })"):format(root))
      H.freeze(child, 2026, 10, 14, 10, 30)
    end,
    post_once = child.stop,
  },
})

--- A fake git repo: a directory with a .git dir.
local function repo(name)
  local dir = work .. "/" .. name
  vim.fn.mkdir(dir .. "/.git", "p")
  vim.fn.mkdir(dir .. "/src", "p")
  return dir
end

local function resolve()
  return child.lua_get(("{ require('logpose.project').resolve(%q) }"):format(root))
end

local function setup(extra)
  child.lua(("require('logpose').setup(vim.tbl_extend('force', { root = %q }, %s))"):format(root, extra))
end

T["resolve"] = MiniTest.new_set()

T["resolve"]["detects the git repo of the current buffer"] = function()
  local dir = repo("Acme API")
  child.cmd("edit " .. vim.fn.fnameescape(dir .. "/src/main.go"))
  eq(resolve(), { "acme-api", "git" })
end

T["resolve"]["falls back to the cwd's repo"] = function()
  local dir = repo("thesis")
  child.cmd("cd " .. dir .. "/src")
  eq(resolve(), { "thesis", "git" })
end

T["resolve"]["is empty outside any repo"] = function()
  eq(resolve(), {})
end

T["resolve"]["never applies inside the journal"] = function()
  vim.fn.mkdir(root .. "/.git", "p")
  child.cmd("edit " .. root .. "/daily/daily-2026-10-14.md")
  eq(resolve(), {})
end

T["resolve"]["projects.paths wins over git, longest match first"] = function()
  local dir = repo("acme-api")
  setup(([[{ projects = { paths = { [%q] = "acme", [%q] = "Acme Backend" } } }]]):format(work, dir .. "/src"))
  child.cmd("edit " .. dir .. "/src/main.go")
  eq(resolve(), { "acme-backend", "path" })
  child.cmd("edit " .. dir .. "/README.md")
  eq(resolve(), { "acme", "path" })
end

T["resolve"]["detect = false disables git detection"] = function()
  local dir = repo("acme")
  setup("{ projects = { detect = false } }")
  child.cmd("edit " .. dir .. "/src/main.go")
  eq(resolve(), {})
end

T["resolve"]["an explicit project wins until cleared"] = function()
  local dir = repo("acme")
  child.cmd("edit " .. dir .. "/src/main.go")
  child.cmd("Logpose project Thesis")
  eq(resolve(), { "thesis", "explicit" })
  H.contains(child.notifications()[1].msg, "project set to thesis")
  child.cmd("Logpose project none")
  eq(resolve(), { "acme", "git" })
  H.contains(child.notifications()[2].msg, "now project acme (from the git repo)")
end

T["require('logpose').project()"] = function()
  child.cmd("Logpose project acme")
  eq(child.lua_get("require('logpose').project()"), "acme")
end

T[":Logpose project without args opens the switcher over known projects"] = function()
  vim.fn.mkdir(root .. "/meetings/thesis", "p")
  setup([[{ projects = { paths = { ["~/work/acme"] = "acme" } } }]])
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.labels = vim.tbl_map(opts.format_item, items)
    _G.prompt = opts.prompt
    cb(items[2])
  end]])
  child.cmd("Logpose project")
  eq(
    child.lua_get("_G.labels"),
    { "  acme    nothing yet", "  thesis  nothing yet", "+ New project…", "  Auto-detect" }
  )
  eq(child.lua_get("_G.prompt"), "Switch project")
  eq(resolve(), { "thesis", "explicit" })
end

T["completes known projects"] = function()
  vim.fn.mkdir(root .. "/meetings/thesis", "p")
  vim.fn.mkdir(root .. "/meetings/acme", "p")
  eq(child.fn.getcompletion("Logpose project ", "cmdline"), { "acme", "thesis", "none" })
end

T["rejects an invalid name"] = function()
  child.cmd("Logpose project ¿?")
  H.contains(child.notifications()[1].msg, "invalid project name")
end

T["meetings"] = MiniTest.new_set()

T["meetings"]["go to meetings/<project>/ with project frontmatter"] = function()
  local dir = repo("acme-api")
  child.cmd("edit " .. dir .. "/src/main.go")
  child.cmd("Logpose meeting retro")
  local path = root .. "/meetings/acme-api/2026-10-14 - retro.md"
  eq(child.api.nvim_buf_get_name(0), path)
  local content = H.read(path)
  H.contains(content, "date: 2026-10-14\nproject: acme-api\ntitle:")
  H.contains(content, "series: acme-api/retro")
  H.contains(
    H.read(root .. "/daily/daily-2026-10-14.md"),
    "## Meetings\n\n- acme-api: [[meetings/acme-api/2026-10-14 - retro|Retro]]\n"
  )
end

T["meetings"]["same title in two projects are both linked"] = function()
  child.cmd("Logpose project acme")
  child.cmd("Logpose meeting retro")
  child.cmd("Logpose project thesis")
  child.cmd("Logpose meeting retro")
  child.cmd("Logpose project none")
  child.cmd("Logpose meeting retro")
  local daily = H.read(root .. "/daily/daily-2026-10-14.md")
  H.contains(daily, "- acme: [[meetings/acme/2026-10-14 - retro|Retro]]")
  H.contains(daily, "- thesis: [[meetings/thesis/2026-10-14 - retro|Retro]]")
  H.contains(daily, "- [[meetings/2026-10-14 - retro|Retro]]")
end

T["meetings"]["meeting_subdir = '' keeps notes flat but tagged"] = function()
  setup([[{ meeting_subdir = "" }]])
  child.cmd("Logpose project acme")
  child.cmd("Logpose meeting review")
  local path = root .. "/meetings/2026-10-14 - sprint-review.md"
  eq(child.api.nvim_buf_get_name(0), path)
  H.contains(H.read(path), "project: acme")
end

T["meetings"]["{project} is available in templates"] = function()
  H.write(root .. "/templates/retro.md", "# {project}: {title}\n{cursor}\n")
  child.cmd("Logpose project acme")
  child.cmd("Logpose meeting retro")
  H.contains(H.read(root .. "/meetings/acme/2026-10-14 - retro.md"), "---\n# acme: Retro\n")
end

T["health shows the active project"] = function()
  child.cmd("Logpose project acme")
  child.cmd("checkhealth logpose")
  H.contains(
    table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    "Project acme (set with :Logpose project)"
  )
end

return T

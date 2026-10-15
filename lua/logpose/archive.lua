--- `:Logpose archive[!]`: move `## YYYY-MM-DD` sections from past periods (weeks or sprints)
--- out of INBOX.md and DONE.md into one archive file per period, merging into existing files.
local config = require("logpose.config")
local date = require("logpose.util.date")
local fs = require("logpose.util.fs")
local markdown = require("logpose.markdown")
local period = require("logpose.period")
local template = require("logpose.template")
local ui = require("logpose.util.ui")

local M = {}

---@param root string
local function jobs(root)
  local opts = config.get()
  local sprint = opts.period.kind == "sprint"
  return {
    {
      name = "inbox",
      source = config.path("inbox", root),
      dest_dir = config.path("journal_entries", root),
      prefix = sprint and opts.affixes.sprint or opts.affixes.week,
      title = opts.archive.journal_title,
    },
    {
      name = "done",
      source = config.path("done", root),
      dest_dir = config.path("done_entries", root),
      prefix = sprint and opts.affixes.done_sprint or opts.affixes.done_week,
      title = opts.archive.done_title,
    },
  }
end

--- Make sure the block ends with a blank line (so a following heading is separated).
---@param block logpose.Block
local function ensure_trailing_blank(block)
  local last = block.lines[#block.lines]
  if last ~= nil and vim.trim(last) ~= "" then
    table.insert(block.lines, "")
  end
end

--- Merge a dated section into `doc`.
--- Same date present -> append the body (skipped if every line is already there, so re-running
--- an interrupted archive never duplicates). Otherwise insert a new section in date order.
---@param doc logpose.Doc
---@param iso string
---@param body string[]
---@param order "newest_first"|"oldest_first"
---@return "merged"|"added"|"skipped"
function M.merge_section(doc, iso, body, order)
  local incoming = markdown.trim_blank(body)

  for _, block in ipairs(doc.blocks) do
    if block.kind == "date" and block.date == iso then
      local old_body = markdown.body(block)
      local existing = markdown.trim_blank(old_body, false, true)
      local have = {}
      for _, l in ipairs(existing) do
        have[l] = true
      end
      local missing = false
      for _, l in ipairs(incoming) do
        if vim.trim(l) ~= "" and not have[l] then
          missing = true
          break
        end
      end
      if not missing then
        return "skipped"
      end
      local trailing = #old_body - #existing
      local lines = { block.lines[1] }
      vim.list_extend(lines, existing)
      vim.list_extend(lines, incoming)
      for _ = 1, trailing do
        table.insert(lines, "")
      end
      block.lines = lines
      return "merged"
    end
  end

  local new_block = { kind = "date", date = iso, lines = { "## " .. iso } }
  vim.list_extend(new_block.lines, incoming)

  local pos
  for i, block in ipairs(doc.blocks) do
    if block.kind == "date" then
      if (order == "newest_first" and block.date < iso) or (order == "oldest_first" and block.date > iso) then
        pos = i
        break
      end
    end
  end
  if pos then
    ensure_trailing_blank(new_block)
    ensure_trailing_blank(doc.blocks[pos - 1])
    table.insert(doc.blocks, pos, new_block)
  else
    ensure_trailing_blank(doc.blocks[#doc.blocks])
    table.insert(doc.blocks, new_block)
  end
  return "added"
end

---@class logpose.ArchiveDest
---@field path string
---@field exists boolean
---@field sections { date: string, status: string }[]

---@class logpose.ArchiveJob
---@field source string
---@field dests logpose.ArchiveDest[]

---@class logpose.ArchivePlan
---@field current logpose.Period  the current period (kept)
---@field jobs logpose.ArchiveJob[]
---@field writes { path: string, content: string }[]  archive files first, then sources
---@field moves integer    number of sections moved

--- Work out what to move, entirely in memory. Nothing is written.
---@param root string
---@param today string
---@return logpose.ArchivePlan
function M.plan(root, today)
  local current = period.of(today)
  local plan = { current = current, jobs = {}, writes = {}, moves = 0 }
  local source_writes = {}
  local configured_order = config.get().section_order

  for _, job in ipairs(jobs(root)) do
    local content = fs.read_file(job.source)
    if content then
      local doc = markdown.parse(content)
      local kept, groups, keys, periods = {}, {}, {}, {}
      for _, block in ipairs(doc.blocks) do
        local p = block.kind == "date" and period.of(block.date) or nil
        -- Compare start dates, not keys: "sprint-9" sorts after "sprint-10" as a string.
        if p and p.start < current.start then
          if not groups[p.key] then
            groups[p.key] = {}
            periods[p.key] = p
            table.insert(keys, p.key)
          end
          table.insert(groups[p.key], block)
        else
          table.insert(kept, block)
        end
      end

      if #keys > 0 then
        table.sort(keys, function(a, b)
          return periods[a].start < periods[b].start
        end)
        local entry = { source = job.source, dests = {} }
        for _, key in ipairs(keys) do
          local path = fs.join(job.dest_dir, job.prefix .. key .. ".md")
          local existing = fs.read_file(path)
          local dest
          if existing then
            dest = markdown.parse(existing)
          else
            local title = template.substitute(job.title, { period = key, period_label = periods[key].label })
            dest = { blocks = { { kind = "preamble", lines = { title, "" } } }, final_newline = true }
          end
          local order = configured_order
          if order == "auto" then
            order = markdown.detect_order(dest) or markdown.detect_order(doc) or "oldest_first"
          end
          -- Insert oldest first so "newest_first" files end up correctly ordered either way.
          table.sort(groups[key], function(a, b)
            return a.date < b.date
          end)
          local sections = {}
          for _, block in ipairs(groups[key]) do
            local status = M.merge_section(dest, block.date, markdown.body(block), order)
            table.insert(sections, { date = block.date, status = status })
            plan.moves = plan.moves + 1
          end
          dest.final_newline = true
          table.insert(entry.dests, { path = path, exists = existing ~= nil, sections = sections })
          table.insert(plan.writes, { path = path, content = markdown.render(dest) })
        end

        -- The source loses its archived sections; tidy blank lines left at the end.
        local last = kept[#kept]
        if last and doc.blocks[#doc.blocks] ~= last then
          last.lines = markdown.trim_blank(last.lines, false, true)
        end
        table.insert(
          source_writes,
          { path = job.source, content = markdown.render({ blocks = kept, final_newline = doc.final_newline }) }
        )
        table.insert(plan.jobs, entry)
      end
    end
  end
  vim.list_extend(plan.writes, source_writes)
  return plan
end

--- Write a plan: refuses up front if any affected file has unsaved changes; archive files are
--- written before the sources, and each write is atomic.
---@param plan logpose.ArchivePlan
function M.execute(plan)
  local paths = vim.tbl_map(function(w)
    return w.path
  end, plan.writes)
  local ok, err = fs.check_writable(paths)
  if not ok then
    error(err, 0)
  end
  for _, w in ipairs(plan.writes) do
    local wrote, write_err = fs.write_file(w.path, w.content)
    if not wrote then
      error(write_err .. " (archive stopped; running it again is safe)", 0)
    end
  end
end

---@param plan logpose.ArchivePlan
---@param root string
---@return string[]
function M.describe(plan, root)
  local function rel(path)
    return require("logpose.link").relpath(root, path)
  end
  local lines =
    { ("Archive sections from before the current %s (%s)"):format(plan.current.kind, plan.current.label), "" }
  for _, job in ipairs(plan.jobs) do
    table.insert(lines, rel(job.source))
    for _, dest in ipairs(job.dests) do
      local dates = vim.tbl_map(function(s)
        return s.status == "skipped" and (s.date .. " (already there)") or s.date
      end, dest.sections)
      table.insert(
        lines,
        ("  → %s (%s): %s"):format(rel(dest.path), dest.exists and "merge" or "new", table.concat(dates, ", "))
      )
    end
    table.insert(lines, "")
  end
  return lines
end

--- Show the plan in a scratch split. Returns the window.
---@param plan logpose.ArchivePlan
---@param root string
---@return integer win
function M.preview(plan, root)
  local lines = M.describe(plan, root)
  table.insert(lines, "q: close")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(buf, "logpose://archive-preview")
  vim.cmd(("botright %dsplit"):format(math.min(#lines, 20)))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
  return win
end

---@param plan logpose.ArchivePlan
local function report(plan)
  local files = #plan.writes - #plan.jobs
  vim.notify(
    ("logpose: archived %d section%s into %d file%s"):format(
      plan.moves,
      plan.moves == 1 and "" or "s",
      files,
      files == 1 and "" or "s"
    ),
    vim.log.levels.INFO
  )
end

---@param opts logpose.CommandOpts
function M.command(opts)
  config.with_root(ui.safely(function(root)
    local plan = M.plan(root, date.today())
    if plan.moves == 0 then
      vim.notify(
        ("logpose: nothing to archive; every section is in the current %s"):format(plan.current.kind),
        vim.log.levels.INFO
      )
      return
    end
    if opts.bang then
      M.execute(plan)
      report(plan)
      return
    end
    local win = M.preview(plan, root)
    vim.ui.select(
      { "Archive", "Cancel" },
      { prompt = "Archive these sections?" },
      ui.safely(function(choice)
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if choice ~= "Archive" then
          vim.notify("logpose: archive cancelled", vim.log.levels.INFO)
          return
        end
        -- Re-plan: files may have changed while the preview was open.
        local fresh = M.plan(root, date.today())
        M.execute(fresh)
        report(fresh)
      end)
    )
  end))
end

return M

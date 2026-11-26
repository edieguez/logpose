-- logpose.nvim: every option, set to its default and explained (https://github.com/edieguez/logpose).
--
-- Copy this file into your Neovim config's lua/plugins/ (LazyVim, or any lazy.nvim setup) and change what you
-- like. Delete the lines you don't change: a deleted line follows logpose's default, while one you keep holds its
-- value even if the default changes later. Tables such as meeting_types, doc_types and people.contacts merge with
-- the defaults (set an entry to false to drop it); lists such as board.columns and workdays replace them whole.
-- Settings that differ between your computers go in a logpose.local.lua: see examples/logpose.local.lua.
-- Without lazy.nvim, give the opts table below to require("logpose").setup().
-- Reference: :help logpose-setup, and the README's Configuration section.
return {
  "edieguez/logpose",
  event = "VeryLazy", -- right after startup, so the keymaps are there before the first :Logpose
  cmd = "Logpose",
  ft = "markdown", -- sooner for a note opened at startup, so it gets gx and [[ / @ completion too
  -- lazy = false, -- or load it at startup, instead of the three lines above
  opts = { -- shared by all your computers; each one's own settings go in logpose.local.lua, beside this file
    -- Journal and files ------------------------------------------------------------------------------------

    -- The journal folder (~ works). Unset, logpose looks for a root_markers file above the current file, then
    -- above the current directory, then uses the folder you chose with :Logpose init.
    -- Set, it wins over all of them.
    -- root = "~/journal",
    root_markers = { ".logpose" }, -- files that mark a journal's root; :Logpose init creates the first
    dirs = { -- folders, relative to the journal's root
      daily = "daily",
      meetings = "meetings",
      notes = "notes", -- topic notes
      projects = "projects", -- project pages, and each project's docs in projects/<name>/
      tasks = "tasks", -- a file per task; :Logpose archive files done ones away in tasks/archive/
      people = "people",
      templates = "templates", -- your own templates, used instead of the plugin's: templates/retro.md…
      reports = "reports", -- where :Logpose report! saves a report
    },
    affixes = {
      daily = "daily-", -- daily notes are daily/daily-2026-10-15.md; "" makes them daily/2026-10-15.md
      week = "week-", -- archive folders for weeks: tasks/archive/week-2026-10-12/
      sprint = "", -- archive folders for sprints: tasks/archive/sprint-43/
    },
    link_style = "wiki", -- links logpose writes: "wiki" ([[notes/x|X]]) or "markdown" ([X](../notes/x.md))
    link_base = "", -- the folder wiki-link targets are relative to ("": the journal's root)
    meeting_filename = "{date} - {slug}", -- {date}, {time} (HHMM), {slug} (needed), {type}; {time} allows several a day
    meeting_subdir = "{project}", -- meeting notes go in meetings/<project>/; "" keeps them all in meetings/
    timestamps = {
      created = true, -- add created: (local time, 2026-10-15T18:57) to new notes
      modified = true, -- add modified: too, kept current as logpose or you change the note
    },

    -- Weeks and sprints ------------------------------------------------------------------------------------

    period = {
      kind = "week", -- what reports, the archive and the board's Done column go by: "week" or "sprint"
      week_start = 1, -- the day weeks start on: 1 = Monday … 7 = Sunday
      sprint = {
        -- The first day of any one sprint, needed with kind = "sprint"; the others are counted both ways.
        -- anchor = "2026-10-15",
        length_days = 14,
        first_number = 1, -- the number of the sprint that starts on anchor
        name = "sprint-{n}", -- how sprints are named, {n} being the number: sprint-43
      },
    },
    workdays = { 1, 2, 3, 4, 5 }, -- the days you work (Monday = 1): the status's Yesterday skips the others

    -- Project detection ------------------------------------------------------------------------------------

    projects = {
      detect = true, -- the git repo you're in is the project: ~/work/Acme API is acme-api
      paths = { -- folder → project, for folders whose name isn't the project's; the longest match wins
        -- ["~/work/acme-api"] = "acme",
      },
      open_board = true, -- switching project opens its board
      hub = true, -- keep an "In this project" list of docs, notes and meetings at the end of project pages
    },

    -- Notes and meetings -----------------------------------------------------------------------------------

    daily = {
      carry_over = true, -- today's new daily note starts with the last one's open to-dos and ## Blockers
      mark_carried = true, -- and marks those to-dos - [>] in the last one, so each lives in one place
      links = true, -- link each daily note to the ones before and after it (previous:/next: in the frontmatter)
      status = { -- ## Yesterday, ## Today and ## Blockers in today's note, from the board, meetings and to-dos
        enabled = true,
        refresh = "open", -- brought up to date when you open today's note; "manual": :Logpose daily refresh
        group_by_project = true, -- :Logpose daily copy groups the status by project; false: a flat list
      },
    },
    series = { -- meetings with the same type and title (or person, for 1:1s), within a project
      carry_over = true, -- a new one starts with the last one's open to-dos under ## Carried over
      mark_carried = true, -- and marks them - [>] in the last one
      links = true, -- link each meeting to the ones before and after it in its series
    },
    default_meeting_type = "adhoc", -- the type the new-meeting form starts on

    -- Meeting types, for :Logpose meeting <key>. label is its name; template its template (default "meeting");
    -- title a fixed title, so nothing is asked; prompt a question asked on the command line instead (title can
    -- then use {input}); ask_attendees = true also asks who's there; order sorts them. Add your own, such as
    -- standup = { label = "Standup", title = "Standup", order = 5 }, and remove one with retro = false.
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
        person = true, -- the answer is a person: an attendee, and their page's ## Next 1:1 items come along
        order = 50,
      },
      adhoc = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
    },

    -- Project doc types, for :Logpose doc <key>, kept in projects/<project>/. label, template (default "doc")
    -- and order as above; statuses are the values status: takes, the first for a new doc. Remove one with
    -- spec = false.
    doc_types = {
      decision = {
        label = "Decision",
        template = "decision",
        order = 10,
        statuses = { "proposed", "accepted", "superseded", "rejected" },
      },
      spec = { label = "Spec", template = "spec", order = 20 },
      runbook = { label = "Runbook", template = "runbook", order = 30 },
      doc = { label = "Doc", template = "doc", order = 40 },
    },

    -- Board and tasks --------------------------------------------------------------------------------------

    board = {
      -- The columns, left to right: key is what a task stores as status: (letters, digits, - and _), label what
      -- the board shows, limit a work-in-progress limit (the count turns red above it), hl the highlight group
      -- for its colour. A list: yours replaces these whole (at least two columns).
      columns = {
        { key = "backlog", label = "Backlog" },
        { key = "todo", label = "TODO" },
        { key = "in-progress", label = "In progress", limit = 3 },
        { key = "follow-up", label = "Follow-up" },
        { key = "done", label = "Done" },
      },
      start = "in-progress", -- reaching this column records started: (it must be one of the keys above)
      done = "done", -- reaching this one records done:; it's where x and :Logpose done move a task
      done_window = "period", -- Done shows the current week or sprint ("period"), or the last N days (a number)
      min_column_width = 24, -- narrower than this, the columns stack vertically
      stale_days = 7, -- cards untouched this many days fade and say idle 9d
      collapsed = {}, -- columns folded when the board opens, such as { "done" }; z folds and unfolds
      border = "column", -- card borders in their column's colour; "project" (the project's) or "neutral"
      icons = "unicode", -- glyphs: "unicode", "nerd" (needs a Nerd Font) or "ascii"
      compact = false, -- start with one-line cards (c toggles)
      lanes = false, -- start with one row per project (s toggles)
      open = "window", -- open the board in the current window, or "tab" for a tab page of its own
    },
    tasks = {
      capture_status = "backlog", -- the column :Logpose capture puts a new task in
      promote_status = "backlog", -- the column for a to-do made into a task (:Logpose promote)
    },

    -- Lists, search and action items -----------------------------------------------------------------------

    lists = { -- :Logpose meetings, notes and people
      max_width = 160, -- rows span the window up to this many columns; on a wider one, the list is centred
      bands = true, -- every other row on a slightly different background (LogposeBand)
    },
    search = {
      live = true, -- with snacks, fzf-lua or Telescope, results follow the prompt as you type; false: fixed ones
    },
    retrieval = {
      -- headings whose every line is searchable, tagged or not (:Logpose find decisions, section:…)
      sections = { "decisions", "blockers", "risks", "open questions" },
    },
    views = { -- saved searches, run with :Logpose view <name>
      -- acme = "tasks open project:acme",
      -- decisions = "decisions sprint:current",
    },
    -- me = "@ana", -- your handle in action items (- [ ] … @ana), for :Logpose actions mine
    actions = {
      include_daily = false, -- also list to-dos in daily notes, not only in meeting notes
      unassigned_mine = true, -- action items without an @owner count as yours in :Logpose actions mine
      output = "quickfix", -- where :Logpose actions lists them: "quickfix" or "picker"
    },
    review = {
      stale_days = 14, -- reports flag open to-dos older than this, and tasks in progress for longer
    },

    -- People -----------------------------------------------------------------------------------------------

    people = {
      -- Ways to reach people: each key is a field on a person's page (email: ana@acme.com). label names it,
      -- show is how its value reads ({value} being the value), open is what o on the people list opens, and
      -- order sorts them. Remove one with email = false.
      contacts = {
        email = { label = "Email", open = "mailto:{value}", order = 1 },
        -- slack = { label = "Slack", show = "@{value}", open = "slack://user?team=T012345&id={value}", order = 2 },
        -- phone = { label = "Phone", open = "tel:{value}", order = 3 },
      },
    },

    -- Interface and integrations ---------------------------------------------------------------------------

    picker = "auto", -- "auto" (snacks, fzf-lua, Telescope, then vim.ui.select), or "snacks", "fzf_lua"…
    keymaps = false, -- true for the <leader>j… key set; { prefix = "<leader>n" } puts it under another prefix
    tickets = {
      pattern = "%u[%u%d]+%-%d+", -- a Lua pattern for ticket IDs: Jira-style PROJ-123
      -- url = "https://acme.atlassian.net/browse/{id}", -- gx on an ID opens it
    },
    telemetry = {
      enabled = true, -- count the commands you use, on this machine only (:Logpose stats); false: none
      retention_days = 180, -- how many days of counts are kept
    },
  },
}

# Spec & plan: `logpose.nvim` — a journal plugin for Scrum/Kanban work in Neovim

> **Handoff note.** This is the implementation spec for `logpose.nvim`. Naming is settled:
> repo `logpose.nvim`, Lua module `logpose` (`require("logpose").setup{}`), user command
> `:Logpose`, `<Plug>(logpose-…)` mappings, `:checkhealth logpose`. It supersedes the earlier
> `journal.nvim` and `cadence.nvim` drafts.
> Work is split into **features in priority order**. Implement and test one feature at a time;
> each feature lists its scope, design, acceptance criteria, and tests. Do not start a feature
> before its dependencies pass their tests.
>
> Settled decisions: **pure Lua**, **Neovim ≥ 0.10**. This spec is the source of truth for
> behaviour; the scripts that inspired it are not part of the project.

---

## 1. Context

The plugin started from three personal helper scripts for a markdown journal: create a daily
note, create a meeting note, and archive past weeks of `INBOX.md`/`DONE.md` into weekly files.
Those scripts are not shared; their behaviour is captured in F1 and F2 below.

The owner is a software developer working in Scrum/Kanban with a daily standup and many other
meetings (planning, refinement, review, retro, 1:1s, ad-hoc), across several projects. The plugin
turns those actions into editor commands and adds the meeting- and sprint-oriented workflow
around them: typed meeting notes, projects, action-item tracking, standup prep, Kanban
capture/done, sprint-aware archives and reports.

## 2. Feature roadmap

| #  | Feature                          | Priority  | Depends on | Replaces / adds                     |
|----|----------------------------------|-----------|------------|-------------------------------------|
| F0 | Foundation                       | Core      | —          | scaffold, config, root, tests, CI   |
| F1 | Daily & meeting notes            | Core      | F0         | new                                 |
| F1.5 | Onboarding (`init`, first run) | Core      | F1         | new                                 |
| F1.6 | Projects                       | Core      | F1.5       | new                                 |
| F2 | Archive                          | Core      | F0         | new                                 |
| F2.1 | Sprint archiving               | Core      | F2         | new (moved up from F7)              |
| F3 | Kanban flow (capture / done)     | High      | F0         | new                                 |
| F4 | Search: index, tags, projects, pickers | High | F1.6, F3 | new                            |
| F5 | Action items & meeting series    | High      | F4         | new                                 |
| O1 | Sections & relative dates      | High      | F4         | new                                 |
| O2 | Inbox triage                   | High      | F3, O1     | new                                 |
| O3 | People                         | High      | F4, F5     | new                                 |
| O4 | Topic notes & backlinks        | Medium    | F4         | new                                 |
| O5 | Saved views                    | Medium    | F4         | new                                 |
| O6 | Maintenance: rename, index cache | Low     | F4         | new                                 |
| F6 | Standup prep                     | Medium    | F1         | new                                 |
| F7 | Reports                          | Medium    | F2.1, F5   | new                                 |
| F8 | Ticket references                | Low       | F0, F4*    | new                                 |

\* soft dependency: works with the `vim.ui.select` fallback, better with F4.

**Milestones**
- **M1 (F0–F2.1): Core journal.** Onboarding, projects, daily and meeting notes, and weekly or
  sprint archiving.
- **M2 (F3–F5): Daily driver.** Capture, complete, find, and follow up on meeting action items.
- **M2.5 (O1–O6): Organize & retrieve.** Capturing is half the job; this milestone covers the
  other half: processing the INBOX, section- and person-aware retrieval, evergreen notes and
  links, saved views, and keeping tags/projects tidy.
- **M3 (F6–F8): Scrum layer.** Standup prefill, period reports with a review section, ticket links.
  (F6 shipped before M2.5; F7 and F8 followed it.) Done as of 0.17.0.
- **Last: T1 local usage telemetry**, once there are features to measure. Done in 0.18.0.
- **B1 Kanban board & task files**, from the first week of real use (0.20.0).

**Releases.** Annotated tags in `MAJOR.MINOR.PATCH` form (no `v` prefix). Each completed feature
bumps the minor version (0.1.0 = F0+F1, 0.2.0 = F1.5, 0.3.0 = F1.6, 0.4.0 = F2, 0.5.0 = F2.1, 0.6.0 = F3, 0.7.0 = F4, 0.8.0 = F5, 0.9.0 = F6, 0.10.0 = O1, 0.11.0 = O2, 0.12.0 = O3, 0.13.0 = O4, 0.14.0 = O5, 0.15.0 = O6, 0.16.0 = F7,
0.17.0 = F8, 0.18.0 = T1, 0.19.0 = live search and previews, 0.20.0 = B1, 0.21.0 = markdownlint-clean notes, 0.22.0 = timestamps, board look and delete, 0.23.0 = peek, scrolling columns, WIP limits and age, 0.23.1 = board resize fixes, 0.24.0 = command menu, statusline, board undo, 0.25.0 = today, keymaps preset, titled notifications, board extras, 0.25.1 = docs rewrite, 0.26.0 = project manager, project completion and board-follows-project fixes, 0.27.0 = project switcher, project pages as registry, moving tasks between projects, merging projects, 0.28.0 = switching opens the board, 0.28.1 = board and projects split into modules, tests 40× faster, 0.28.2 = caching for big journals, 0.29.0 = frontmatter editor, 0.30.0 = capture picks the project, form rework, bulk edits, 0.30.1 = completion menu closes after a choice, 0.30.2 = <CR> accepts from the menu, nvim-cmp off in the form, 0.31.0 = the edit form stays open after saving, 0.32.0 = card redesign, 0.32.1 = automatic project colours, no cursorline on the board, 0.33.0 = borders tinted with the project's colour, 0.34.0 = column-coloured borders by default again, tags as chips, 0.35.0 = shared date wording and frontmatter writer; triage, move and the switcher removed, 0.36.0 = new-task form, 0.37.0 = linked notes on cards, recently edited notes on today, 0.38.0 = tasks, notes and to-dos kept apart; INBOX, DONE and migrate removed, 0.39.0 = notes screen, 0.40.0 = new-note forms, 0.40.1 = gx follows note links, 0.40.2 = promoted to-dos start in Backlog, 0.40.3 = gx works alongside a markdown plugin's, 0.41.0 = notes from tasks; promoted to-dos keep their text, 0.42.0 = people: a list, forgiving matching, completion in notes, 0.43.0 = people pages and the people screen, 0.44.0 = to-dos and their tasks in step, 0.45.0 = "no project" mode, 0.46.0 = filter language with or/not/fields; meetings, notes and people lists, 0.47.0 = filter bar, help windows, lists polish, 0.48.0 = counts work on the board and the lists); fixes bump the patch;
1.0.0 once M3 is done.

---

## 3. Conventions used across features

**Command surface.** One user command with subcommands and completion:
`:Logpose <subcommand> [args]`. Every subcommand also gets a `<Plug>(logpose-…)` mapping.
No keymaps are set by default; suggested ones go in the README.

**Dates.** ISO `YYYY-MM-DD` strings everywhere; compare them lexicographically. All date
arithmetic goes through `util/date.lua`, anchored at **12:00 local time** to avoid DST bugs.

**Tasks, notes and to-dos** (0.38.0; the words every command, screen, search and doc uses).
- A **task** is a task file in `tasks/` (B1): frontmatter with `status`, `project`, `tags`,
  `due`, `blocked`…, shown on the board. Done tasks of past periods move to
  `tasks/archive/<period>/`.
- A **note** is what you write: daily notes, meeting notes, topic notes, project pages.
- A **to-do** is a checkbox `- [ ] text` / `- [x] text` inside a note (or a task file's
  checklist). Optional inline metadata, parsed from F5 on: `@owner`, `due:YYYY-MM-DD`. Meeting
  to-dos are action items. `:Logpose promote` turns a to-do into a task.
- In the index (`index.lua`) these are item kinds `note`, `task`, `todo` (plus `line`, tagged or
  retrievable lines); `file_type` says where the file sits (daily, meeting, topic, project,
  task, other) and `index.is_file(it)` is true for notes and tasks.

**Journal files** (default layout, relative to the journal root; every path is configurable via
`dirs`, so an existing journal keeps its own layout in config).
- Daily notes: `daily/daily-YYYY-MM-DD.md`.
- Meeting notes: `meetings/<project>/YYYY-MM-DD - <slug>.md`.
- Topic notes: `notes/<slug>.md`; project pages: `projects/<project>.md`.
- Tasks: `tasks/<slug>.md`, archived ones in `tasks/archive/<period>/`.

**Links.** `config.link_style = "wiki"` (default, `[[meetings/2026-10-14 - retro|Retro]]`) or
`"markdown"` (`[Retro](<../meetings/2026-10-14 - retro.md>)` — angle brackets because of spaces).
All link generation goes through `link.lua`.

**Writes.** Every file write goes through `util/fs.lua`: write to a temp file in the same
directory, then `vim.uv.fs_rename`. Before writing a file that is open in a buffer, check
`vim.bo[buf].modified`; if modified, abort with an error naming the file. After writing, reload
clean open buffers (`:checktime` on that buffer).

---

## 4. Plugin layout

```
plugin/logpose.lua          -- registers :Logpose (works without setup(); config resolved lazily)
lua/logpose/
  init.lua                  -- setup(opts)
  config.lua                -- defaults, merge, validation, root resolution
  commands.lua              -- subcommand dispatcher + completion
  health.lua                -- :checkhealth logpose
  template.lua              -- template lookup + variable rendering + {cursor}
  link.lua                  -- wiki/markdown link generation
  markdown.lua              -- section parse/render helpers (shared by archive, tasks, standup)
  util/date.lua             -- today, now, parse_iso, add_days, monday_of, workday math
  util/text.lua             -- slugify (with transliteration), trim
  util/fs.lua               -- join, mkdir_p, read_lines, atomic write, buffer safety
  notes/daily.lua           -- F1
  notes/meeting.lua         -- F1 (+ F5 series hooks)
  archive.lua               -- F2
  tasks.lua                 -- F3
  index.lua                 -- F4 journal index (notes, tasks, tagged lines)
  query.lua                 -- F4 filter language (project:, #tag, type:, open/done …)
  search.lua                -- F4 :Logpose find / grep
  picker/init.lua           -- F4 adapter (pick items, grep)
  picker/{snacks,fzf_lua,telescope,select}.lua
  actions.lua               -- F5
  standup.lua               -- F6
  period.lua                -- F2.1 (week/sprint periods)
  report.lua                -- F7
  tickets.lua               -- F8
templates/                  -- default templates shipped with the plugin
  daily.md  meeting.md  planning.md  refinement.md  review.md  retro.md  1on1.md
doc/logpose.txt
tests/                      -- mini.test specs + fixtures
.github/workflows/ci.yml
Makefile                    -- `make test`, `make lint`
```

---

## F0 — Foundation (Core)

**Goal.** A loadable, configurable, testable skeleton. No user-facing note features yet.

**Scope**
1. Repo scaffold per §4, README stub, `doc/logpose.txt` stub, MIT license (owner's call).
2. `config.lua` defaults:
   ```lua
   {
     root = nil,                 -- absolute path; overrides the root saved by :Logpose init
     root_markers = { ".logpose" },  -- generic defaults since F1.5 (were C1's journal/… layout)
     dirs = {
       daily = "daily",                   meetings = "meetings",
       inbox = "INBOX.md",                done = "DONE.md",
       journal_entries = "journal-entries",
       done_entries = "done-entries",
       templates = "templates",           -- user overrides; falls back to plugin templates/
       reports = "reports",
     },
     affixes = { daily = "daily-", week = "week-", done_week = "done-week-" },
     link_style = "wiki",
     workdays = { 1, 2, 3, 4, 5 },        -- ISO weekday numbers, Mon=1
     picker = "auto",                     -- added in F0 so health can report it; used by F4
   }
   ```
   Feature-specific keys are added by their features. Unknown keys → warning, not error.
   Invalid values → error. Lists (`workdays`, `root_markers`) are replaced, not merged.
3. **Root resolution** (in order): configured `root` (expand `~`) → `vim.fs.root(current buffer,
   root_markers)` → `vim.fs.root(cwd, root_markers)` → the root saved by `:Logpose init` (F1.5)
   → error "logpose: journal root not found; run :Logpose init or set `root` in setup()". A bare `journal/` directory is **not** a marker (too many false
   positives). The configured path comes first because the owner is usually editing a *work*
   repo when a meeting starts.
4. `util/date.lua`: `today()`, `now_hhmm()`, `parse_iso(s)`, `add_days(iso, n)`,
   `weekday(iso)` (ISO, Mon=1), `monday_of(iso)`, `is_workday(iso)`,
   `prev_workday(iso)`, `next_workday(iso)`.
5. `util/text.lua`: `trim`, `slugify` — transliterate Latin accents first (á→a, é→e, í→i, ó→o,
   ú→u, ü→u, ñ→n, plus uppercase), then lowercase, `[^a-z0-9]+` → `-`, strip leading/trailing `-`.
   Empty result → caller supplies a fallback.
6. `util/fs.lua`: atomic write and buffer-safety rules from §3.
7. `commands.lua`: dispatcher with subcommand completion; unknown subcommand → error listing
   valid ones.
8. `health.lua`: reports Neovim version, resolved root (and how it was resolved), whether each
   configured dir exists, which picker backend is detected.
9. Test harness: **mini.test** run headless (`make test`), with a temp-dir journal fixture helper.
   CI matrix: Neovim 0.10.4 (minimum supported), stable and nightly, on Ubuntu. Tests run with
   `TZ=America/New_York` so date math crosses real DST changes.

**Acceptance criteria**
- `:checkhealth logpose` runs and reports the root, from both inside and outside the journal repo.
- `:Logpose <Tab>` completes subcommands (empty list for now is fine).
- `make test` passes locally and in CI.

**Tests**
- `monday_of`: every weekday of a week maps to that Monday; Sunday maps to the previous Monday;
  year boundary (2026-01-01 → 2025-12-29); a DST-change week.
- `prev_workday`/`next_workday` across a weekend.
- `slugify`: `"Reunión de planeación"` → `"reunion-de-planeacion"`; `"  Sprint 42 — Retro!! "` →
  `"sprint-42-retro"`; `"¿?"` → `""`.
- Root resolution order, using temp dirs with and without markers.
- Atomic write: content correct, no temp file left behind; aborts on a modified buffer.

---

## F1 — Daily & meeting notes (Core)

**Goal.** Create-or-open daily and meeting notes, cursor ready, from any buffer. Replaces the
two note scripts.

### F1.1 Templates (`template.lua`)
- Lookup order: `<root>/<dirs.templates>/<name>.md` → plugin `templates/<name>.md`.
- Variables: `{date}`, `{time}`, `{weekday}` (e.g. "Wednesday"), `{iso_week}`, `{title}`,
  `{type}`, `{attendees}`, `{series}`, `{previous}`, `{sprint}` (empty unless a sprint anchor is configured, F2.1).
- Render with a **function replacement**: `tpl:gsub("{([%w_]+)}", function(k) ... end)`. Never
  pass user text as a `gsub` replacement string — a `%` in a title would break it. Unknown
  variables are left untouched.
- `{cursor}` marks where the cursor lands; it is removed from the written file. If absent, the
  cursor goes to the last line.

### F1.2 Daily note (`:Logpose daily [date|prev|next|today]`)
- Default date is today. `prev`/`next` are relative to the **current buffer's** daily note date if
  it is one, else today, and use workday math.
- Path `<dirs.daily>/daily-<date>.md`. Missing → render `daily` template and write. Always open
  (`:edit`) and place the cursor.
- Default `templates/daily.md`:
  ```markdown
  # {date} daily notes

  ## Yesterday

  ## Today
  {cursor}

  ## Blockers

  ## Meetings

  ## Notes
  ```
  The daily note doubles as personal standup prep (F6 fills in "Yesterday"). There is therefore
  no `standup` meeting type by default; add one through config if team-level standup notes are
  wanted.

### F1.3 Meeting note (`:Logpose meeting [type] [date]`)
- Config:
  ```lua
  meeting_types = {
    planning   = { label = "Sprint planning", template = "planning",   title = "Sprint planning" },
    refinement = { label = "Refinement",      template = "refinement", title = "Refinement" },
    review     = { label = "Sprint review",   template = "review",     title = "Sprint review" },
    retro      = { label = "Retrospective",   template = "retro",      title = "Retro" },
    ["1on1"]   = { label = "1:1",             template = "1on1",       prompt = "Person: ",
                   title = "1:1 {input}" },
    adhoc      = { label = "Ad-hoc",          template = "meeting",    prompt = "Meeting title: " },
  },
  meeting_filename = "{date} - {slug}",   -- may include {time}, e.g. "{date} {time} - {slug}"
  ```
- Flow: no type argument → `vim.ui.select` over type labels. A type with `prompt` →
  `vim.ui.input`; a type with a fixed `title` → no prompt (one keystroke to a planning note).
  **All creation logic runs inside the async callbacks.** Empty/nil input → `vim.notify` and abort.
- Slug from the final title; empty slug → `type` name as fallback.
- **Existing-note rules:**
  - Format without `{time}`: path exists → open it, never overwrite.
  - Format with `{time}`: if a note with the same date and slug exists, `vim.ui.select`
    "Open existing" / "Create new"; otherwise create.
- Written notes start with frontmatter, then the template body:
  ```markdown
  ---
  type: retro
  date: 2026-10-14
  title: Retro
  attendees: []
  series: retro
  ---
  ```
  (`series` is filled in now so F5 can use it: the type name for fixed-title types; for types
  with a prompt, `<type>-<slug of the input>`, e.g. `1on1-ana`, `adhoc-reunion-con-qa`.)
- Types are ordered by an `order` field in the picker; set a type to `false` to remove it; a type
  without `template` uses `meeting`. Wiki links are relative to `link_base` (default `""`, the root).
- Default `templates/meeting.md`: `# {date} - {title} meeting notes`, then `## Notes`
  (cursor here — notes come first during a meeting), `## Decisions`, `## Action items` (`- [ ] `). Type templates add their own sections:
  - planning: Sprint goal / Committed items / Risks / Action items
  - refinement: Items discussed / Estimates / Open questions / Action items
  - review: Demoed / Feedback / Action items
  - retro: Went well / To improve / Action items
  - 1on1: Topics / Feedback / Follow-ups (as `- [ ]` tasks)

### F1.4 Link into the daily note
After creating a meeting note, add a link to it under `## Meetings` in that date's daily note.
Create the daily note (from its template, without opening it) if missing; create the heading if
missing; skip if the link is already present. If the daily note is open with unsaved changes, add
the link to the buffer (left unsaved) instead of refusing.

**Acceptance criteria**
- From a buffer in an unrelated repo, `:Logpose daily` creates and opens today's note with the
  cursor under `## Today`; running it again opens the same note.
- `:Logpose daily prev` on a Monday opens Friday's note.
- `:Logpose meeting planning` creates `<today> - sprint-planning.md` with no prompt, frontmatter
  present, cursor in the template; today's daily note links to it.
- `:Logpose meeting adhoc` with title `Reunión con QA` → filename `<today> - reunion-con-qa.md`,
  content keeps `Reunión con QA`.
- Same type and title on the same day opens the existing note (default filename format).
- A user template in `journal/templates/retro.md` overrides the shipped one.

**Tests**
- Template rendering: all variables, a title containing `%` and `{`, `{cursor}` removal and position.
- Filename generation with and without `{time}`; empty-slug fallback.
- Daily link insertion: heading missing, heading present, link already present (idempotent).
- Daily header `# {date} daily notes`; meeting header `# {date} - {title} meeting notes`;
  filename `{date} - {slug}.md` (accented titles transliterated).

---

## F1.5 — Onboarding (Core)

**Goal.** A new user gets a working journal without editing their config.

**Design** (`onboard.lua`, `state.lua`)
- `state.lua`: JSON in `stdpath("data")/logpose/state.json`; `get(key)`, `set(key, value)`.
- `:Logpose init [dir]` — no argument → `vim.ui.input` (prompt "Journal directory: ", default:
  the saved root or `~/journal`, `completion = "dir"`). Then:
  - a file → error; missing or empty directory → create it with `dirs.daily`, `dirs.meetings`,
    `INBOX.md` (`# INBOX`), `DONE.md` (`# DONE`); existing non-empty directory → nothing scaffolded;
  - write the first `root_markers` entry if missing (never `.git`);
  - save the root to state; notify; warn if `setup({ root })` points elsewhere (it wins).
- Root resolution gains a last step: the saved root (ignored if the directory is gone).
- `config.with_root(fn)`: commands that need a root (`daily`, `meeting`, and every later feature)
  call it. No root → the first-run prompt ("No journal found. Create one at: "), then continue
  the original command with the new root. Cancel → warning naming `:Logpose init`. A configured
  but missing `root` is an error, never a prompt. Validate arguments (e.g. meeting type) before
  prompting.
- Health reports "saved by :Logpose init" as a root source and suggests `:Logpose init` when no
  root is found.
- Generic defaults (§3): paths relative to the root, `.logpose` marker, `link_base = ""`.

**Acceptance criteria**
- In a fresh Neovim with no config, `:Logpose daily` asks for a directory, creates the journal,
  and opens today's note in it; afterwards commands work from any buffer.
- `:Logpose init ~/existing-notes` only adds `.logpose`; existing files are untouched.
- Tests never touch the real `stdpath("data")` (each child gets its own `XDG_DATA_HOME`).

**Tests**
- Scaffold vs existing directory, spaces and `~` in paths, file instead of directory, custom
  `dirs`/markers, prompt defaults and cancel, saved-root precedence, first run from `daily` and
  `meeting`, configured-but-missing root, directory completion.

---

## F1.6 — Projects (Core)

**Goal.** Work on several unrelated projects in **one** journal: one daily note and standup
across everything, but meetings, tasks and reports can be kept apart and filtered per project.

**Design** (`project.lua`)
- Config:
  ```lua
  projects = {
    detect = true,      -- use the git repo of the current buffer/cwd as the project
    paths = {},         -- { ["~/work/acme-api"] = "acme", ["~/school/thesis"] = "thesis" }
  },
  meeting_subdir = "{project}",  -- meetings/<project>/…; "" keeps everything in meetings/
  ```
- **Active project** (first match wins): set with `:Logpose project <name>` (kept in state until
  changed or cleared) → longest `projects.paths` prefix of the current buffer/cwd → the git repo
  name (slugified) of the current buffer/cwd, unless that repo is the journal itself → none.
- `:Logpose project [name|none]`: set or clear; no argument → pick from known projects or type
  a new one. Completion lists known projects. **Known projects** (0.26.0): the pinned one,
  `projects.paths`, project pages (`projects/*.md`), subdirectories of `meetings/`, and the
  `project:` of any note or task; archived projects are left out (search still lists them).
- Switching (or archiving, renaming) fires `User LogposeProjectChanged`; an open board
  re-resolves its project and redraws, and the statusline cache is cleared.
- **Project pages are the registry** (0.27.0): `projects/<name>.md` frontmatter holds `title`
  (display name), `description`, `paths` (repo folders: detection checks them after
  `projects.paths` and before the git repo, source `page`), `color` (hex or highlight group,
  used for the project's cards and lanes on the board), `archived` and `merged_into`.
- **Switcher** (`:Logpose project` without a name, `P` on the board, 0.27.0): the picker
  lists the active project, then recently switched-to ones (`recent_projects` in state), then
  the rest by activity; each item previews the project's details (below). "+ New project…"
  creates a page and switches; "Auto-detect" unpins.
- Switching to a project (manager `<CR>`, `:Logpose project <name>`) shows its board
  unless `projects.open_board = false` or the current buffer is already a board, which follows
  the switch itself (0.28.0). Unpinning doesn't open it.
- **Project manager** (`:Logpose projects`, `projects/`: `summary`, `manager`; the switcher was
  removed in 0.35.0; 0.26.0, reworked in 0.27.0): one
  row per project with open tasks (and how many are in the start column), overdue, due soon
  (3 days), blocked, meetings, notes, and the newest change as "3d ago"; most recently active
  first; no change for `review.stale_days` fades the row. `<Tab>` expands a project in place:
  description, name, repo folders, in-progress, blocked (with reasons), due, last meeting and
  recent notes; `<CR>` on those lines opens them. Keys: `<CR>` pin, `c` unpin, `b` board, `n`
  page, `t` open tasks, `f` notes, `a` add (name, then repo folder, suggested from the
  previous window's repo), `p` link a repo folder, `R` rename, `M` merge, `D` archive, `U`
  restore, `A` show archived, `r` refresh, `q` close, `?` help.
- **Frontmatter editor** (`:Logpose edit`, 0.29.0, reworked in 0.30.0; `e` on the board and in
  the project manager). `edit/fields.lua` is the model: fields per note type (plus keys the note
  has), `check(kind, key, text)` returning a normalised value, an error message or a note (never
  throwing, so the form checks as you type), `collect` (all fields → values, errors, notes,
  changes) and `effects` (what saving does, one line each). `edit/form.lua` is the window: the
  buffer holds one value per line; field names are inline virtual text (`right_gravity = false`),
  hints/errors/notes are end-of-line virtual text, and the summary, managed keys (`created
  modified started done series order merged_into archived`) and the key help are virtual lines
  below. Invisible marks (one per field line) tell which field a line was after `dd`, a paste or
  `J`; `repair` restores one line per field (a deleted line clears its field, extra lines join the
  field above) joined to the change with `:undojoin`. Insert `<CR>`/`<Tab>` move between fields,
  `<C-a>`/`<C-x>` cycle fixed sets and step dates, normal `<CR>` picks with `vim.ui.select`.
  Completion as you type uses the built-in popup (completion plugins are turned off in that
  buffer). `edit/save.lua` writes plain fields with `fs.update_lines`, a task's
  `status`/`project`/`blocked` through `taskfile.set_*` (logged), and moves a meeting to its new
  project's folder (`series`, links via `maintenance.rewrite_links`, the daily `- project:` label,
  the emptied folder). A project page's `project` is refused (rename with `R`).
- **Consolidation** (0.35.0): one way to word dates (`util/date`: `due` for due dates
  everywhere they're shown, `relative`, `short`, one `MONTHS` table), one frontmatter writer
  (`frontmatter.lua`: `quote`, `render`, `line`, `read`, `set` with `false` to remove and an
  optional key order; used by task files, project pages, meeting and topic notes and the edit
  form). Retired: `:Logpose triage` (the board, and in INBOX mode the inbox triage queue),
  `:Logpose move` (the edit form and `m`), the project switcher (`:Logpose project` without a
  name and `P` open the manager; switching shows the existing board via `board.show`, keeping
  its filter, marks and folds) and the `<leader>jw` key.
- **New-task form** (0.36.0): `:Logpose capture` without text and `a` on the board open
  `fields.load_new` (title, status, project, tags, due, blocked, `context`) seeded with the
  column / detected project / lane. The title's emptiness isn't an error until save
  (`give the task a title`); `fields.new_effects` describes the task to be created; `save.create`
  makes it with `taskfile.create` (context as the body, `set_blocked` after) and announces a
  project only when it's new. The form then reloads as an edit of the created file. On the
  board the creation and each later save are separate undo steps.
- **Linked notes** (0.37.0): `links.related(root, items)` maps each task file to the notes linked
  with it both ways (non-task notes linking to it; non-task notes it links to), resolving only
  links whose target name matches a task file (or that leave a task), newest first. `collect`
  stores it as `it.related`; `cards.details` adds `✎ N` (`LogposeBoardNotes`) after the project,
  before the project (which is shortened for it) and set apart by a space; `n` (`actions.notes`) opens one directly or several in the picker.
  The index records each note's `mtime`; today's "Recently edited" lists the five newest
  daily, meeting, topic and other notes (not tasks or project pages) edited within seven days, excluding
  today's daily note, with `date.ago`. The edit form notes attendees not yet in the journal
  (`new: Maria`).
- **Card design** (0.32.0, `board/cards.lua`): colour only where it means something. Borders use
  `LogposeBoardBorder` (`board.border = "column"` restores column colours); the focused card has
  a heavy border in Normal's foreground plus `LogposeBoardFocusBg` (CursorLine) under its rows,
  drawn by the view at a low priority so other colours stay on top. `cards.state` decides the
  look: done (dimmed title with ✓, `LogposeBoardDoneBorder`), blocked (red left edge `┃` and
  reason; never faded), stale (faded title, `idle Nd` in `LogposeBoardStale`; only once past
  `board.stale_days`). `cards.details` fits the details line by importance, not by cutting
  the end: the due text (`cards.due_text`: `overdue Nd`, `due today`/`due tomorrow`, the weekday
  within a week, else `due D Mon`) and idle time always; then the project (shortened, or only
  its colour mark below six cells; left off on a one-project board and in rows per project);
  then whole tags. Projects without a `color:` get one automatically (0.32.1,
  `project.palette`/`auto_hl`): highlight groups every scheme defines, minus greys (low
  chroma) and hues within 20° of one already kept or of the board's meaning colours (error, warn,
  ok); handed out as a set over the journal's projects (hash slot, else the next free one) so they
  differ while there are enough colours. The board window turns `cursorline` off. `board.border`: "column" (the
  default again since 0.34.0, after trying the others in use), "project" (`cards.project_border`
  mixes the project's colour 60/40 with Normal's background; otherwise the colour itself) or
  "neutral". Tags are chips (0.34.0): ` #tag ` in `LogposeBoardTag`, Normal's foreground on a
  background mixed 22% toward it (`Visual` without true colours), set apart by a space.
- **Bulk edits** (0.30.0): `v` marks cards on the board (`b.marked`, by file; pruned to visible
  cards on render; `V`/`<Esc>` clear). `H` `L` `1`–`9` `x` `b` `m` `e` act on every marked card as
  one undo step (`actions.targets`, `with_card`). `e` with marks, or `:'<,'>Logpose edit` in a
  quickfix list, opens `fields.load_bulk`: shared values filled in, differing ones empty (= keep);
  `none` clears project/due/blocked; `tags` takes `+a -b` (per-task add/remove) or a list
  (replace). `save.bulk` applies per task, skipping tasks that already hold the value.
- **Capture picks the project** (0.30.0): `taskfile.take_project` reads `+name` /
  `project:name` (`+none` = none; `+` must start a word and be followed by a letter) in capture,
  the board's `a`, promote and migrate. `due:` goes through `date.resolve_due` (also weekday
  names). The prompt and the confirmation name the project and why (`tasks.describe_project`:
  pinned, projects.paths, its folder, this repo, this board, this row); `tasks.last` and `:Logpose
  edit last` reopen the last capture. With rows per project, `a` uses the row under the cursor
  (`view.lane_at_cursor`, from `b.lane_rows`). `tasks.complete_text` completes `+`, `#`, `due:`
  for the command line and (`complete_input`, customlist) for `vim.ui.input` prompts.
- **Moving tasks** (0.27.0): `m` on the board (undoable) and the edit form's `project` set
  `project:` and log `project: old → new` (`:Logpose move` was removed in 0.35.0).
- **Merging** (`M`, `:Logpose merge-project old new`, 0.27.0): the rename plan with `merge`:
  meeting files move into the existing folder one by one (a name clash aborts), the emptied
  folder is removed, links and series follow; if both projects have pages the old page stays
  with `archived: true` and `merged_into: new`. Renaming onto an existing project is refused
  with a pointer to merge.
- **Archiving** sets `archived: true` in the project page (created if missing). Notes and tasks
  stay in place and searchable; the project leaves completion, the project picker and the
  all-projects board, and is unpinned if it was pinned. A board scoped to it still shows it.
- Meeting notes (F1): saved under `meetings/<project>/` when a project is active; frontmatter
  gains `project: acme`; `{project}` template variable; the series key is project-scoped
  (`acme/retro`) so recurring meetings never mix across projects. The daily-note link is
  prefixed with the project: `- acme: [[meetings/acme/2026-10-14 - retro|Retro]]`.
- `require("logpose").project()` returns the active project (for statuslines).
- Later features use it: F3 capture tags items `#acme`; F4 search, F5 actions and F7 reports
  default to "all", with a `project` argument (`current` = active project).
- Health shows the active project and how it was chosen.
- Project names are slugs (`Acme API` → `acme-api`); `auto` (`detect`, `clear`) unpins and
  detects again. `none` (0.45.0) means no project: `state.project = false`, `resolve` returns
  `nil, "none"` and detects nothing; `:Logpose meeting <type>` and `:Logpose note <title>` then
  open the new-note form (type or title filled in) so the project is picked per note.
- The daily-link duplicate check matches the exact link target, so `retro` in two projects (or
  `retro` vs `retro-2`) are distinct links.

**Acceptance criteria**
- Inside `~/work/acme-api`, `:Logpose meeting retro` creates `meetings/acme-api/<date> - retro.md`
  with `project: acme-api`; the daily note links it under `## Meetings` with the project prefix.
- `:Logpose project thesis` overrides detection until `:Logpose project auto`.
- With no project (e.g. editing the journal itself), notes go to `meetings/` as in F1.

**Tests**
- Resolution order (explicit, paths prefix, git, journal repo excluded, none); slugified names;
  subdir and frontmatter; project-scoped series; `meeting_subdir = ""`; completion.

---

## F2 — Archive (Core)

> **Superseded in 0.38.0.** INBOX.md, DONE.md and their section archives are gone;
> `:Logpose archive` now moves done task files of past periods to `tasks/archive/<period>/`
> (see C1). The design below is history.

**Goal.** Move `## YYYY-MM-DD` sections from past weeks out of `INBOX.md`/`DONE.md` into one
archive file per week, with a preview + confirm step and safe writes.

**Design** (`archive.lua`, using `markdown.lua`)
- `markdown.lua` parses a file into blocks: preamble (before the first `## `), date sections
  (`## YYYY-MM-DD` + body) and other `## ` sections. `parse → render` is lossless.
- Grouping goes through a **period function** — `period.of(iso) -> { key, start, finish, label }`
  — Monday weeks by default; F2.1 adds configurable weeks and sprints. Periods are compared by
  start date, never by key.
- Jobs: `inbox → journal_entries/<affixes.week><key>.md`, `done → done_entries/<affixes.done_week><key>.md`.
  Date sections in the current (or a future) period stay; preamble and non-date sections stay.
- New archive files start with `archive.journal_title` / `archive.done_title`
  (`# Journal: {period_label}`, `# Done: {period_label}`; `{period}` is the key).
- Merging into an archive file: a new date is inserted in date order (`section_order`: "auto"
  follows the file, then the source, else oldest first); an existing date gets the moved body
  appended — unless every line is already there (so re-running after an interrupted archive
  never duplicates).
- `:Logpose archive` → build a plan in memory → show it in a scratch split (`logpose://archive-preview`,
  `q` closes) listing, per source, destination file (new/merge) and section dates →
  `vim.ui.select { "Archive", "Cancel" }`. On confirm, re-plan (files may have changed) and
  execute. `:Logpose archive!` (or `:Logpose! archive`) skips the preview.
- Execute: check buffer safety for **every** file first (all-or-nothing), write the archive files,
  then rewrite `INBOX.md`/`DONE.md` without the moved sections (no trailing blank lines left).
  Atomic writes; clean open buffers reload.
- Nothing to archive (or no INBOX/DONE) → notify and stop; no files touched.

**Acceptance criteria**
- Past-week sections end up in the right weekly files, current-week sections stay.
- A second run reports nothing to archive.
- With `INBOX.md` open and modified, the archive aborts and names the file; nothing is written.

**Tests (fixtures inline in `tests/test_archive.lua`)**
- Single and multiple weeks, DONE.md, merge into an existing week file (new and same-date
  sections), newest-first files and forced `section_order`, year boundary, preamble and non-date
  sections kept, trailing blank lines, everything archived, nothing to archive, missing files,
  second run, interrupted run, unsaved buffer, buffer reload, preview content, cancel, custom
  dirs/affixes/titles.
- Unit: `parse → render` round-trip is lossless; block classification; order detection.

**Milestone M1** after F2.

---

## F2.1 — Sprint archiving (Core)

**Goal.** Archive by the team's sprints (two weeks, Thursday to Wednesday) instead of Monday weeks.

**Design** (`period.lua`)
- Config:
  ```lua
  period = {
    kind = "week",           -- or "sprint"
    week_start = 1,          -- ISO weekday weeks start on; 4 = Thursday
    sprint = {
      anchor = nil,          -- start date of any one sprint; required for kind = "sprint"
      length_days = 14,
      first_number = 1,      -- number of the sprint starting on `anchor`
      name = "sprint-{n}",
    },
  },
  affixes = { sprint = "", done_sprint = "done-" },  -- sprint-42.md / done-sprint-42.md
  ```
- `period.of(iso)`: weeks start on `week_start`; sprints are counted in fixed steps of
  `length_days` from `anchor`, forward and backward (`n = first_number + floor(days / length)`).
  Label: `week of 2026-10-08` or `sprint-42 (2026-10-01 – 2026-10-14)`.
- The archive groups by period and compares start dates (so `sprint-9` is older than
  `sprint-10`). Sprint files use `affixes.sprint`/`affixes.done_sprint` + the sprint name.
  Switching kinds never rewrites existing archive files.
- `{sprint}` in templates is the sprint name whenever an anchor is set (any `kind`).
- Health shows the period kind and the current period. Validation: `kind`, `week_start` 1–7,
  ISO `anchor` (required for sprints), positive `length_days`, integer `first_number`.

**Acceptance criteria**
- With a Thursday anchor and 14 days, dates Thursday…the second Wednesday share one sprint file.
- `{sprint}` and archive filenames match the configured calendar.

**Tests**
- Periods: anchor sprint, forward/backward, year boundary, DST, every day of a year lands in a
  sprint starting on the anchor weekday, name format; Monday and Thursday weeks.
- Archive: sprint files (INBOX and DONE), sprint 9 vs 10, preview label, Thursday weeks.
- Config validation; `{sprint}` in templates; health.

---

## F3 — Kanban flow: capture & done (High)

> **Superseded.** Capture makes task files since B1, and since 0.38.0 there is no INBOX mode:
> `done` finishes the task file you're in, `check` toggles to-dos (see C1). History below.

**Goal.** Get items into INBOX and move finished ones to DONE without leaving the current buffer.

**Design** (`tasks.lua`)
- `:Logpose capture [text]` — no text → `vim.ui.input`. Appends `- [ ] text` under today's
  `## <today>` section in `INBOX.md` (file and section created if missing; sections placed per
  `section_order`, shared with the archive). With an active project (F1.6) the item gets
  ` #project` unless the text already has it. An exact duplicate in today's section is skipped.
- `:Logpose done` (current line, a `:range`, or visual mode via `<Plug>(logpose-done)`):
  - In `INBOX.md`: remove the task line(s), add them as `- [x] …` under today's section in `DONE.md`.
  - In any other journal file (meeting, daily…): check it off in place and add
    `- [x] text ([[link|note]])` to DONE. Already-checked items are reported, not re-logged.
  - Non-task lines are skipped with a notice; `DONE.md` itself and files outside the journal are refused.
- Writes to INBOX/DONE follow the §3 rules (an unsaved INBOX/DONE buffer gets the edit in the
  buffer instead). Edits to the *current* buffer go through the buffer API so `u` undoes them,
  then the buffer is saved — unless it already had unsaved edits, which are never saved for you.

**Acceptance criteria**
- `:Logpose capture Fix flaky test` from a work repo adds the task under today in INBOX, tagged.
- `:Logpose done` on an INBOX task moves it to DONE under today; `u` in INBOX restores the line.
- `:Logpose done` on an action item in a meeting note checks it and logs it in DONE with a link.

**Tests**
- Task parsing; capture: new file/section, existing section, newest/oldest-first, project tag,
  prompt/cancel, duplicate, unsaved and clean INBOX buffers.
- Done: INBOX move, undo, range and visual `<Plug>` with non-task lines, meeting note link,
  already checked, buffer with prior unsaved edits, newest-first DONE, refusals, nothing to do.

---

## F4 — Search: index, tags, projects, pickers (High)

**Goal.** Find notes, tasks, tags and projects quickly, with whichever picker is installed
(snacks.picker is LazyVim's default; fzf-lua and Telescope also supported). Search behaviour
lives in logpose, so every picker shows the same results.

**Design**
- **Index** (`index.lua`): scans every `*.md` under the root (skipping dot-dirs and
  `dirs.templates`) into plain items; F5 and F7 reuse it.
  - Note item per file: `kind = "note"`, `file`, `lnum = 1`, `text` (frontmatter `title`, else
    the first `# ` heading, else the filename), `date` (frontmatter `date`, else a date in the
    filename), `note_type` (`daily`, `meeting`, `inbox`, `done`, `archive`, `other`, by location),
    `type` (meeting type from frontmatter), `project` (frontmatter), `tags`.
  - Task item per `- [ ]` / `- [x]` line: `kind = "task"`, `checked`, `text`, `lnum`, `date` (the
    enclosing `## YYYY-MM-DD` section, else the note's date), the note's `project` and
    `note_type`, inline `tags`.
  - Line item per other line with an inline tag: `kind = "line"`.
  - Tags: inline `#word` (letters, digits, `_`, `-`, `/`; not pure numbers; must start a word, so
    headings and URLs fragments don't count) plus frontmatter `tags:` (`[a, b]` or `a, b`).
    Compared case-insensitively. A note's tags include its frontmatter tags and inline tags.
- **Query** (`query.lua`): `:Logpose find` arguments after the scope are filters, all ANDed:
  `project:acme` (matches the item's project **or** a `#acme` tag), `#perf` / `tag:perf`,
  `type:retro`, `open` / `done` (tasks), `since:YYYY-MM-DD`, `until:YYYY-MM-DD`; other words
  must all appear in the text (case-insensitive).
- **Picker adapter** (`picker/`): `pick(items, { prompt, on_choice })` with `display`, `file`,
  `lnum` per item (file preview where supported), and `grep({ cwd, text })`.
  Backend: `config.picker = "auto"` (snacks → fzf_lua → telescope → select) or forced.
  `select` uses `vim.ui.select`; its grep fills the quickfix list via `:vimgrep`.
  Default action opens the file at the line.
- **Commands** (`search.lua`):
  - `:Logpose find [scope] [filters…]` — scope `notes` (default), `daily`, `meetings`, `archives`,
    `tasks`, `tags`, `projects`.
  - `tags` lists every tag with its count; choosing one lists everything carrying it.
  - `projects` lists projects (index + F1.6 known projects); choosing one lists its notes and tasks.
  - Notes sort newest first; tasks too, open before done.
  - `:Logpose grep [text]` — the backend's live grep in the journal (prompt when empty for `select`).
  - Completion: scopes, then `project:<known>`, `#<known tag>`, `type:<meeting type>`, `open`, `done`.

**Acceptance criteria**
- `:Logpose find meetings project:acme` lists only acme meetings, newest first, in any backend.
- `:Logpose find tasks open #perf` lists open tasks tagged `#perf` across INBOX and notes.
- `:Logpose find tags` → choose `#perf` → its tasks, lines and notes.

**Tests**
- Index: note metadata (frontmatter, heading, filename date, location type), tasks with section
  dates, tags (inline, frontmatter, exclusions, case), skipped dirs.
- Query parsing and matching for every filter.
- Picker: backend detection; each backend's call shape and confirm action with stub modules;
  `select` end to end; grep fallbacks.
- Commands: scopes, filters, tags → items, projects → items, sorting, completion.

---

## F5 — Action items & meeting series (High)

**Goal.** Action items from meetings don't get lost, and each recurring meeting starts from the
previous one.

### F5.1 Action items (`actions.lua`, on the F4 index)
- `:Logpose actions [open|mine|overdue|all] [filters…]` — tasks from meeting notes (plus daily
  notes with `actions.include_daily = true`); same filters as `:Logpose find`.
- Inline metadata: `@owner` (start of a word, so e-mail addresses don't count) and
  `due:YYYY-MM-DD`. `me = "@emmanuel"` defines `mine`; unassigned items count as mine unless
  `actions.unassigned_mine = false`. `overdue` = open with `due` before today.
- Output: quickfix list (default; title `logpose actions: <mode> <filters>`) or the picker
  (`actions.output = "picker"`). Order: open first, soonest due, then oldest meeting. Overdue
  items are flagged.
- Empty `- [ ]` placeholders from templates aren't tasks (index-wide).
- Completing an item works with F3's `:Logpose done` from the opened buffer.

### F5.2 Meeting series (in `notes/meeting.lua`)
- On creation, the previous note is the most recent earlier meeting with the same `series`
  (frontmatter; project-scoped since F1.6). If found:
  - `Previous: [[…|<title> <date>]]` is inserted right after the title heading;
  - with `series.carry_over` (default), a `## Carried over` section follows with the previous
    note's open tasks, each `- [ ] text (from [[…|<date>]])`; an older `(from …)` is replaced,
    so an item carried several times keeps one, current, origin;
  - with `series.mark_carried` (default), those tasks become `- [>] …` (migrated) in the previous
    note, so `actions` and search don't list them twice. An unsaved previous note is edited in
    its buffer.
- Later: completion of past titles/people in the meeting prompt.

**Acceptance criteria**
- With retros containing open items, `:Logpose actions` lists them in quickfix with correct
  lines; `overdue` filters by due date.
- A second `1on1` with the same person links the previous one and carries its open follow-ups;
  a 1:1 with a different person, or the same title in another project, does not.

**Tests**
- Metadata parsing; modes, `me`/unassigned, filters, include_daily, picker output, ordering,
  empty result, completion.
- Series: link + carried section + cursor, `[>]` marking and no double listing, other person,
  other project, carried twice, latest earlier note only, both options off, unsaved previous
  note, markdown links.

---

## F6 — Standup prep (Medium)

**Goal.** The daily note arrives with "Yesterday" already written and unfinished work carried.

**Design** (`standup.lua`, hooked into daily-note creation only — never modifies an existing note)
- Previous note = the most recent existing daily note before the new date (weekends, vacations).
- From its `## Today` section:
  - checked tasks → `## Yesterday` as plain bullets (`- text`); other non-empty lines (notes,
    plain bullets) are copied as they are; `- [>]` lines are skipped;
  - open tasks → the new `## Today` (`standup.carry_forward`, default on), and with
    `standup.mark_carried` (default) they become `- [>]` in the previous note so they're
    tracked once; empty placeholders are ignored.
- `standup.include_done = true` also lists that day's `DONE.md` entries under Yesterday
  (without duplicating lines already there).
- Items go right after each heading; the cursor stays on the empty line after the carried tasks.
- Section names configurable: `standup.sections = { yesterday, today, blockers }`.
- `:Logpose standup [date]` opens a read-only scratch buffer (`logpose://standup/<date>`, `q`
  closes) with Yesterday / Today / Blockers of that day's note (unsaved edits included). With
  `standup.group_by_project` (default) items tagged with a known project are grouped under
  `### <project>`, the rest under `### other`; empty sections show `- (none)`.

**Acceptance criteria**
- Monday's new note gets Friday's done items in "Yesterday" and open tasks in "Today".
- An existing daily note is never modified by re-running `:Logpose daily`.

**Tests**
- Prefill content and cursor, `[>]` marking and single listing, each option off, include_done,
  no previous note, existing note untouched, custom section names.
- Standup view: grouping, flat output, unsaved edits, missing note.

---

## M2.5 — Organize & retrieve

Design rule for the whole milestone: structure lives in the plain markdown (frontmatter, tags,
headings, `[[links]]`, `@mentions`) and the index reads it; no hidden database.

## O1 — Sections & relative dates (High)

**Goal.** Ask for "decisions on acme this sprint" or "blockers last week" directly.

**Design**
- Index (F4): every task/line item records `section` — the nearest `## ` heading above it
  (lowercased; date headings are not sections). Tagged-line items stay; additionally, every
  non-empty line under a **retrievable section** becomes a `line` item even without tags.
  Retrievable sections: `retrieval.sections = { "decisions", "blockers", "risks", "open questions" }`.
- Query (F4): `section:decisions` (substring, case-insensitive) and scopes `find decisions`,
  `find blockers` (shorthand for `section:<name>` over lines and tasks).
- Relative dates in every date filter and wherever a date is accepted:
  `today`, `yesterday`, `-7d` / `+3d`, `-2w`; period filters `week:current|-1|+1` and
  `sprint:current|-1|<n>` (expands to that period's start..finish via F2.1; `sprint:<n>` needs a
  sprint anchor).
- Display shows the section for lines: `Decision text  · Retro › Decisions`.

**Acceptance criteria**
- `:Logpose find decisions project:acme sprint:current` lists decisions from acme meetings in
  the current sprint, newest first.
- `:Logpose actions overdue since:-14d` works.

**Tests**
- Section tracking (nested headings, date headings, frontmatter), retrievable sections without
  tags, relative date parsing (each form, invalid forms), week/sprint expansion incl. no anchor.

*Implementation notes:* `### ` sub-headings stay in their `## ` section; `section:` accepts
dashes for spaces (`section:open-questions`).

## O2 — Inbox triage (High)

> **Removed** in 0.35.0 (triage) and 0.38.0 (INBOX). History below.

**Goal.** Process INBOX item by item instead of letting it grow.

**Design** (`triage.lua`)
- `:Logpose triage [filters]` walks open INBOX tasks, oldest first. For each, a picker/select
  of actions (one keypress where the backend allows):
  - `project` — add `#project` (known projects + new);
  - `tag` — add tags; `due` — add `due:` (relative dates from O1 accepted); `owner` — add `@owner`;
  - `move` — move the line into a note (pick a meeting/topic/project note; appended under
    `## Action items`, or `## Notes` if missing) and remove it from INBOX;
  - `done` — as F3; `someday` — move under `## Someday` in INBOX (created if missing);
    `drop` — delete the line (asks once per session to confirm drops);
  - `skip`, `quit`.
- Edits use the buffer API when INBOX is open (undoable), otherwise safe writes (§3).
- Ends with a summary: processed / moved / done / dropped / remaining.

**Acceptance criteria**
- Triaging three items (project, move, drop) leaves INBOX and the target note as expected;
  `u` in an open INBOX buffer restores the last change.

**Tests**
- Each action, oldest-first order, filters, someday creation, quit midway, unsaved INBOX buffer.

## O3 — People (High)

**Goal.** "Everything involving Ana": 1:1s, meetings she attended, items she owns, mentions.

**Design** (`people.lua`, index additions)
- Index: notes get `people` from frontmatter `attendees:` and, for prompted types like `1on1`,
  the prompt answer (stored as frontmatter `with: Ana` from now on); tasks/lines get people from
  `@mentions`. People are slugs (`ana`, `bob-smith`); display keeps the original spelling.
- Query: `person:ana` / `@ana` filter matches any of the above.
- `:Logpose find people` lists people with counts → choose one → their notes, tasks and lines,
  open action items first.
- Meeting creation: `attendees` prompt for types with `ask_attendees = true` (comma-separated,
  completion from known people); `1on1` fills `attendees: [Ana]` automatically.
- Meeting prompts complete past inputs (people for 1:1s, titles for ad-hoc) via
  `customlist` completion (the F5.2 leftover).

**Acceptance criteria**
- After a 1:1 with Ana, a retro she attended and a task `@ana`, `:Logpose find people` → Ana
  lists all three.

**Tests**
- People extraction (attendees, with:, mentions), slugging, filter, people scope, attendee
  prompt and completion.

## O4 — Topic notes & backlinks (Medium)

**Goal.** A home for knowledge that isn't tied to a day: project pages, how-tos, decision
records, and the links between notes.

**Design** (`notes/topic.lua`, `links.lua`)
- `dirs.notes = "notes"`, `dirs.projects = "projects"`.
- `:Logpose note [title]` creates/opens `notes/<slug>.md` (frontmatter `title`, `created`,
  `project` when active, `tags: []`; template `note`). `:Logpose project-page [name]` opens
  `projects/<name>.md` (template `project`: overview, links, decisions) — the hub for a project.
- Index learns links: `[[target|label]]` and relative markdown links → `links` on each note.
- `:Logpose backlinks` (current note) lists notes and lines linking to it; `:Logpose links`
  lists outgoing links.
- Completion source for `[[` (blink.cmp and nvim-cmp adapters; optional, auto-registered when
  available) offering note titles → inserts a wiki or markdown link per `link_style`.

**Acceptance criteria**
- From a project page, `:Logpose backlinks` lists the meetings and daily notes that link to it.

**Tests**
- Link parsing (wiki with/without label, markdown, relative paths), backlink resolution,
  note/project-page creation, completion source items.

## O5 — Saved views (Medium)

**Design**
- `views = { acme = "tasks open project:acme", decisions = "decisions sprint:current" }`.
- `:Logpose view [name]` runs `:Logpose find <view>` (no name → pick a view). Views can be
  used as `<Plug>`-style keymaps: `<cmd>Logpose view acme<cr>`.

**Tests**
- Expansion, unknown view, completion.

## O6 — Maintenance (Low)

**Design**
- `:Logpose rename-tag old new` and `:Logpose rename-project old new` (tags, frontmatter
  `project:`, meeting subfolder) with a preview + confirm like the archive; never touches
  unsaved buffers.
- Index cache keyed by file path + mtime + size, kept in memory per session; invalidated on
  `BufWritePost` inside the journal.

**Tests**
- Renames across inline tags, frontmatter, folders; preview/cancel; cache hit/miss/invalidation.

---

## F7 — Reports (Medium)

**Goal.** Summaries per week or sprint (periods from F2.1) for reviews, retros and status updates.

**Design** (`report.lua`)
- `:Logpose report [week|sprint] [offset]` (default: the configured period kind; offset `0` =
  current, `-1` = previous) opens a markdown scratch buffer with:
  - DONE items in the period (from `DONE.md` and the period's done archive), grouped by date;
  - meetings held in the period (title + link), grouped by type and project;
  - open action items created in the period (reusing F5).
  `:Logpose report! …` also writes it to `<dirs.reports>/<period key>.md`.
- Optional `project` argument limits the report to one project (F1.6).
- **Review section** (M2.5): decisions made in the period (O1); open tasks older than
  `review.stale_days` (14); INBOX items older than a period; captures without a project; overdue
  actions per project and person (O3).

**Acceptance criteria**
- `:Logpose report sprint -1` summarises the previous sprint correctly on fixture data, including
  the review section.

**Tests**
- Report assembly on fixtures for weeks and sprints, offsets, project filter.

---

## F8 — Ticket references (Low)

**Goal.** Ticket IDs in notes are links.

**Design** (`tickets.lua`)
- Config: `tickets = { pattern = "%u+%-%d+", url = "https://<org>.atlassian.net/browse/{id}" }`
  (disabled if `url` is nil).
- In journal buffers only (buffer-local, via `FileType markdown` + root check): `gx` on a ticket
  ID opens the URL with `vim.ui.open`; otherwise falls through to default `gx`.
  Since 0.40.1 `gx` is mapped in every journal note, ticket URL or not: a link under the cursor
  (`links.at`: `[[target|label]]` anywhere on it, `[label](path)` / `[label](<path>)` to a file)
  resolved by `links.follow` opens the note (an unresolved wiki link warns); anything else calls
  the `gx` mapping the buffer had before (captured at attach: a markdown plugin's or Neovim's),
  or `vim.ui.open(<cfile>)`. `<cfile>` alone stopped at the space in
  `[[meetings/acme/2026-10-14 - retro|Retro]]`.
  Since 0.40.3 the mapping is set in a `vim.schedule` after `FileType`, so it wraps a markdown
  plugin's buffer-local `gx` whichever loads first; with such a plugin (`maparg().buffer == 1`)
  logpose takes only wiki links and tickets and runs the plugin's mapping (expr or not) for the
  rest, so its anchors (`file.md#heading`), footnotes and URLs keep working. Checked against
  markwright.nvim in both setup orders.
- `:Logpose ticket [ID]` (default: ID under cursor) greps the journal for it via F4.
- Optional highlight group `LogposeTicket`.

**Acceptance criteria**
- `gx` on `PROJ-123` opens the configured URL; `gx` on a normal URL still works.
- `:Logpose ticket PROJ-123` lists every note mentioning it.

**Tests**
- Pattern extraction at cursor positions (start, middle, end of ID, adjacent punctuation).
- Mapping is not set outside the journal root.

---

## T1 — Local usage telemetry (Low, last)

**Goal.** Know which features are actually used, to decide what to polish, simplify or drop.
Strictly local: nothing ever leaves the machine.

**Design** (`telemetry.lua`)
- On by default (opt-out with `telemetry = { enabled = false }`): the data is local to the
  current user and never leaves the machine. Documented in the README and health. (Opt-in
  until 0.26.0.)
- Recorded per event: subcommand (and scope/mode for `find`, `actions`, `report`), date, and
  whether it succeeded. No note content, paths, titles, tags or arguments beyond the
  scope/mode keyword.
- Storage: `stdpath("data")/logpose/usage.json` — counts per command per day, kept for
  `telemetry.retention_days` (180), written at most once per minute and on `VimLeavePre`.
- `:Logpose stats [days]` shows a scratch buffer: commands by use count, trend (last 7 vs
  previous 7 days), never-used commands, and per-scope breakdowns. `:Logpose stats!` resets.
- Health reports whether telemetry is on and where the file is.

**Acceptance criteria**
- After using `daily` 3× and `find tasks` 2×, `:Logpose stats` shows those counts; with
  telemetry off nothing is written.

**Tests**
- Recording, privacy (no args/paths stored), retention pruning, throttled writes, stats view,
  reset, disabled mode.

---

## B1 — Kanban board & task files (High)

**Goal.** Fix the problems found in real use: open work was invisible (nothing opened INBOX),
finishing a task depended on cursor position, and a one-line checkbox can't hold the context
a real task has. Tasks become files and the board becomes the place you see and move them.

**Task files** (`taskfile.lua`)
- One file per task: `tasks/<slug>.md` (`dirs.tasks`; `-2`, `-3`… on collisions), from the
  `task` template. Frontmatter, in this order: `title`, `status`, `project`, `tags`, `due`,
  `blocked` (empty, or the reason), `created`, `started`, `done`, `order` (optional).
  The body is free markdown (context, links, checklists) ending in a `## Log` section.
- Status is a board column key. Moving a task updates `status`, sets `started` the first time
  it reaches `board.start` and `done` when it reaches `board.done` (cleared if it leaves),
  and appends `- YYYY-MM-DD HH:MM: TODO → In progress` to `## Log`. Blocking appends
  `blocked: <reason>` / `unblocked`. Writes follow §3 (an unsaved buffer gets the edit).
- `tasks.mode = "files"` (default) or `"inbox"` (the F3/O2 INBOX/DONE flow, unchanged).

**Board** (`board/`: `text`, `cards`, `collect`, `view`, `history`, `actions`, `keys`, and
`init`, which opens boards and re-exports the parts; split in 0.28.1): `:Logpose board [filters]`
- A scratch buffer (`filetype=logpose-board`) in the current window. Default columns:
  Backlog · TODO · In progress · Follow-up · Done (`board.columns`, a list of `{ key, label }`).
  Columns sit side by side; when a column would be narrower than `board.min_column_width`
  (24) they stack vertically.
- Cards show the title (up to two lines), a `⛔ <reason>` line when blocked, and
  `project · #tags · due MM-DD` (overdue due dates highlighted). Order in a column: `order`,
  then due date, then created. Done shows tasks finished in the current period
  (`board.done_window = "period"`, or a number of days). Archived tasks never show.
- Scope: the active project's tasks (project field or `#project` tag); all tasks when there
  is none. Filters use the `find` language (`#perf`, `due` via `until:`, `@ana`…).
- Keys: `h`/`l` column, `j`/`k` card (the cursor and mouse also select);
  `H`/`L` (or `<`/`>`) move the card one column; `1`–`9` move it to that column; `x` done;
  `b` block/unblock (asks for a reason); `J`/`K` reorder within the column; `a` add a card to
  the focused column; `<CR>` open the task file (coming back re-renders the board);
  `/` filter, `p` project/all, `r` refresh, `q` close, `?` help, `D` delete (asks first).
  Cards are boxes (heavy border when focused), columns coloured via `LogposeBoardColumnN`
  highlight groups, no trailing whitespace on any line. Moves are counted in usage
  stats as `board move`/`board done`/`board block`.

**Commands in files mode**
- `capture [text]` creates a task in `tasks.capture_status` (Backlog) with the active project;
  `capture!` also opens it to add context.
- `done`: in a task file, moves it to Done; on a checkbox elsewhere, checks it off in place.
  (In INBOX.md it still moves the line to DONE.md.)
- `triage` opens the board on the Backlog column.
- `:Logpose migrate[!]` turns open INBOX tasks into task files (Backlog; `due:` → `due`,
  `#tags` → `tags`, a tag naming a known project → `project`, the section date → `created`;
  `## Someday` items get tag `someday`) and removes them from INBOX. Preview first; `!` skips
  it. DONE.md stays as history.
- `:Logpose promote` on a checkbox line (meeting, daily, any note) creates a task file in
  `tasks.promote_status` (Backlog since 0.40.2) with the note's project and a `From:` link, and turns the line
  into a link to it.

**Everything else reads task files**
- Index: files under `dirs.tasks` are notes of type `task` with `status`, `blocked`, `due`,
  `created`, `done_date`. `find tasks` lists them with checkbox tasks; new filters
  `status:<key>` and `blocked`; `open`/`done` work on them.
- Standup adds a **Board** part: done on the previous workday, in progress now, blocked
  (under Blockers).
- Report: tasks done in the period go under Done; the review lists blocked tasks and tasks in
  progress since before `review.stale_days`.
- Archive also moves done tasks from earlier periods into `tasks/archive/<period>/`.
- Health shows the task count per column.

**Acceptance criteria**
- `:Logpose capture fix flaky test` from a work repo creates a Backlog task for that project;
  `:Logpose board` shows it; `L` twice puts it In progress with `started` set and a log line;
  `x` moves it to Done; the next day's standup lists it under Yesterday.
- `b` with "waiting on ana" marks the card ⛔ and puts it under Blockers in the standup.
- `:Logpose migrate` turns three INBOX items into task files and empties those lines.

**Tests**
- Task file creation (slugs, collisions, template, frontmatter), status moves (timestamps,
  log, unsaved buffer), block/unblock, reorder.
- Board: layout side by side and stacked, focus by keys and cursor, moves, add, filter,
  scope toggle, done window, re-render on return, help.
- capture/done/triage in both modes, migrate (fields, Someday, preview, `!`), promote.
- Index fields and `status:`/`blocked` filters; standup Board part; report sections;
  archive of done tasks; health.

---

## C1 — Tasks, notes and to-dos kept apart (0.38.0)

**Goal.** "Task" meant three things (task files, checkboxes in notes, INBOX.md lines), so search,
commands and screens mixed them. Keep one word per thing, everywhere.

**Design**
- Index kinds `note`, `task`, `todo`, `line` (was `note` for tasks, `task` for checkboxes);
  `note_type` renamed `file_type`; `index.is_file`. Notes and tasks both carry `links`, `mtime`,
  `fm_tags`; `links.all`, `[[` completion (tasks marked `task ·`) and `links.related` read both.
- `todos.lua`: `parse` (was `tasks.parse_task`), `check` / `:Logpose check` (toggles the to-dos
  on a line or range: checks them, or unchecks when all are checked; API edits, so `u` undoes),
  `promote` (moved from the removed `migrate.lua`).
- `:Logpose done` only moves the task file you're in to Done; elsewhere it errors and points at
  `check`.
- Search scopes: `notes` (notes only), `tasks` (live task files), `todos` (checkboxes);
  `archives` removed. `open`/`done` apply to tasks (status) and to-dos (checked); `status:` and
  `blocked` to tasks.
- Today: a `## Tasks` part (in progress, blocked, due soon) and a `## Notes` part (meetings
  today, to-dos left in today's note, overdue action items, recently edited).
- Projects screen: `o` lists the project's open to-dos beside `t` (tasks) and `f` (notes).
- Keymap preset grouped as notes, tasks and to-dos (`x` checks a to-do, `X` finishes a task,
  `o` open to-dos); the edit form's title names what it edits (`Edit task · …`).
- Removed: INBOX.md, DONE.md, `tasks.mode`, `:Logpose migrate`, section archives
  (`dirs.inbox/done/journal_entries/done_entries`, `affixes.done_*`, `archive.*_title`,
  `section_order`, `standup.include_done`) and the markdown section-document helpers.
  `:Logpose archive` moves done tasks only. Reports list "Done tasks" and "Open to-dos older
  than N days".

## C2 — Notes screen (0.39.0)

**Goal.** Tasks have the board; notes had only search. Give notes a screen to browse.

**Design** (`notes/browse.lua`, `:Logpose notes [filters]`)
- `collect(root, { project, filter })`: `kind == "note"` items in scope (the project by
  `project:` or a `#project` tag, so tagged daily notes count) matching the find filters, newest
  first by date (or mtime when undated), each with its open to-do count and the number of tasks
  linked with it (`links.related`, inverted).
- `build(state, entries, width)`: `# Notes · <project title | all projects>`, a filter line,
  then sections by type (Meetings, Topic notes, Daily notes, Project pages, Other notes) or by
  project (`g`; "No project" last; rows prefixed with the meeting type or file type). Rows:
  date, title (a daily note's weekday), `☐ N to-dos`, `→ N tasks`, `◆ project` (all-projects
  view grouped by type). The title column fits the longest title shown (12–48 cells). Sections
  show `M.SHOWN` (8) rows and a `… N more` row; headings fold.
- Keys: `<CR>` (open / fold / show more), `e` (edit form, re-rendering on save), `/` (filter
  prompt with find-filter completion), `p` (this project / all), `g`, `z`, `n`, `d`, `b`, `r`,
  `q`, `?`. Re-renders on `BufEnter`, keeping the cursor on the same note.
- Default scope is the active project (`project.resolve`); the projects screen's `f` opens it
  for that project. Keymap preset: `<leader>jl`. Highlights `LogposeNotes*`.

## C3 — New-note forms (0.40.0)

**Goal.** Set a note's frontmatter (tags above all) while creating it, as the new-task form does
for tasks.

**Design**
- `fields.load_new_note(root, kind, defaults)`: `meeting` (`type`, `title`, `date`, `project`,
  `attendees`, `tags`; first type, today, the active project) or `topic` (`title`, `project`,
  `tags`). `model.new` with a non-task kind.
- A new meeting's `title` follows its type (`meeting.title_for(key, field)`): empty → the type's
  title; another text → replaces it (series unchanged); for a type with a `prompt` it's the
  answer (`input`: a 1:1's person, an ad-hoc title) and can't be empty. `fields.meeting_title`
  sets the hint (`r.hints.title`, which the form prefers over `HINTS`), the note (`→ 1:1 Ana`)
  and `r.meeting`. Title candidates: people for person types, past titles of the type otherwise.
  Type candidates follow `meeting.types()` order.
- Preview (`new_effects(model, r, ctx)`): for a meeting, `fields.build_meeting` runs
  `meeting.build` (cached in the form's ctx by its inputs) to say the path, the daily-note link,
  and what the series carries over (`carry over N open to-dos from <title> (<date>)`, or `link
  the previous …`); an existing file → `open the existing …`. Topic: the path, project, tags.
- `meeting.build(..., extra)`: `extra.title` overrides the title (and slug), `extra.tags` adds
  `tags:`. `meeting.write(root, note, no_open)` (was the local `write_and_open`). `topic.note`
  takes `{ project, tags, open }` and returns `path, cursor, existed`; `topic.note_path`.
- Saving (`save.create_note`) creates the note without opening it; the form then closes itself
  and opens the note at the template's cursor. A note that exists is opened untouched.
- Entry points: `:Logpose meeting` without a type (a date-only argument prefills `date`),
  `:Logpose note` without a title, the notes screen's `a` (by section), `n`, `m`
  (`edit.open_new_note`). The edit form for existing meetings gains `tags`.

## C4 — Promotion, both ways (0.41.0)

**Goal.** "Promote" moves things up a level, and both ends link to each other: a to-do becomes a
task, a task's write-up becomes a note.

**Design**
- To-do → task (`todos.promote`): unchanged task creation (`From: [[note]]` in its body), but the
  to-do keeps its text and gains an indented `→ [[task|task]]` line under it (it used to be
  replaced by the link; a line of its own keeps long items within markdownlint's limit), so an
  action item keeps its `@owner` and `due:` and stays in `:Logpose actions`. A to-do inside a
  task file can be promoted too.
- Task → note (`notes/from_task.lua`): `:Logpose promote` in a task file not on a to-do (or with a
  range), `N` on the board (`actions.to_note`). `M.rows(lines, l1, l2)`: the body rows without
  the `## Log` and `## Notes` sections and `From:` lines, blank ends trimmed. The new-note form
  (`load_new_note(root, "topic", { from_task = info })`, titled "Note from task") adds a
  `content` field (`copy` | `move`, a CHOICES field). Preview: create or add to the note, `copy|move
  the task's write-up (N lines; ## Log left out)` or `the N selected lines`, `link the note and
  the task to each other`. `M.apply`: the note gets `From: [[task]]` + the write-up (a new note
  via `topic.note(..., { body })`, an existing one at its end); the task gets `- [[note]]` under
  `## Notes` (created before `## Log`), and with `move` loses the write-up rows (recomputed from
  its current lines). The board's `✎` count picks the note up through `links.related`.

## C5 — People suggestions (0.42.0)

**Goal.** Suggest the right person while typing attendees, wherever that happens.

**Design** (`people.lua`, `completion/init.lua`)
- `people.known(root)`: the index's people (count, and involvement per project) merged with the
  list file `people.md` (replaced by people pages in C6).
- `people.match(people, query, project)`: `plain()` (lowercase, Latin accents stripped) on both
  sides; rank 1 the name or handle starts with it, 2 a word of the name does, 3 it's inside;
  then the project's people (by involvement there), then overall involvement. Used by the edit
  form (attendees, `with`, a person-type meeting's title; items carry `equal = 1` and the menu is
  re-asked on `TextChangedP`, so Vim doesn't narrow it by prefix), the `customlist` prompts
  (`LogposeCompletePeople`, without names already typed) and the note sources.
- `completion.items(line, col, row, bufnr)` for blink.cmp / nvim-cmp: `[[` → link items (now
  notes and tasks); in the frontmatter, an `attendees:` line (after `[` or a comma, names already
  there left out, quoted for YAML when needed) or a `with:` line → people; `@partial` after a
  space or punctuation → `@slug`. The note's `project:` ranks. `filterText` adds the plain
  spelling so the plugins' own fuzzy filters match without accents. Triggers `[`, `@`, `,`; the
  cmp keyword pattern also takes `@handle` and words.

## C6 — People pages (0.43.0)

**Goal.** A compendium of the people you work with: a page per person (name, role, how to reach
them, your notes about them) that the rest of logpose knows about, so completion, filters and
`gx` treat "Ana", `@ana` and "Ana López" as one person.

**Design** (`people/init.lua`, `people/screen.lua`, `people/rename.lua`)
- Storage: `people/<slug>.md` (`dirs.people`). Frontmatter `name`, `aliases` (list), `role`,
  `projects` (list) and one key per way to reach them; the body is free notes (no heading: the page's title is `name`). The
  index gives these files `file_type = "person"`, `kind = "person"`, the title from `name` and the
  raw frontmatter as `fields`. `people.md` (`people.file`) is gone.
- Ways to reach people are configured, not hard-coded: `people.contacts = { key = { label, show,
  open, order } }`. `show` and `open` are templates over `{value}` (`@{value}`,
  `mailto:{value}`, `slack://user?team=T0&id={value}`). The default is `email` only; Slack,
  Teams, Matrix, a phone… are a config entry, so moving to another chat app is a config change.
  Keys may not clash with the page's own keys. A page's keys not in the config still show (by
  key) and are kept.
- `people.known(root)`: pages first (each with `slugs`: file stem, name and alias slugs), then the
  index's people merged into a page when any slug matches; counts and per-project involvement
  from the index (a page's `projects` count too). `people.find` resolves any name, alias or
  handle; `people.expand(slug)` gives every slug of that person, so `person:`/`@` filters match
  all of them. `people.match` (C5) also ranks aliases.
- Forms: `edit` on a person page shows name, aliases, role, projects and every configured
  contact; the new-person form (`kind = "person"`) creates the page (`people.create`) and opens it
  below the frontmatter. Email is checked for an `@`.
- `:Logpose people [filter]` (`<leader>ju`): people with a page (role, contacts as shown, `met`
  latest meeting, open to-dos owned, projects), most recently met first; then "In your notes, no
  page yet". `<Tab>` expands meetings, open to-dos, tasks and notes involving them (`<CR>` opens
  one); `<CR>` opens the page (or the form to add one), `e` edit, `a` add, `m` 1:1 (the first
  person-type meeting type), `y` copy / `o` open a contact (`vim.ui.select` when several), `R`
  rename, `/` filter (name, alias, role, project), `p` this project / everyone.
- `:Logpose person [handle]`: their page, or the form to add one. Completion offers handles.
- `gx` on an `@mention` or a name on an `attendees:`/`with:` line opens the person's page when
  there is one; otherwise the usual `gx`.
- `:Logpose find people` shows display names with role, first contact and how much involves them
  (with filters, only people involved in the matches); a page-only person opens their page.
- `:Logpose rename-person[!] handle New Name` (or `R`; without a new name it asks): the page moves
  to the new slug (links follow, via `maintenance.rewrite_links`), its `name` changes and the old
  name joins `aliases`; attendees/`with:` entries and `@mentions` that used the old name or
  handle are rewritten (other aliases are left alone: they still resolve). Same preview/confirm as
  `rename-tag` (`maintenance.confirm_and_apply`).

**Possible future work** (not planned yet)
- Carry a person's open "## Next 1:1" items into the next 1:1's agenda.
- Merge two people (`M` on the screen): fold one page into another, combining aliases, contacts
  and notes, and rewrite references like a rename.

**Tests** (`test_people.lua`, `test_people_screen.lua`)
- Pages and aliases merge with mentions; filters expand aliases; the form creates a page with
  contacts; the screen's sections, details, filter, project toggle, copy/open contacts, 1:1;
  `:Logpose person`; `gx` on a mention and an attendee; rename moves the page and rewrites
  attendees, `with:`, mentions and links.

## C7 — To-dos and their tasks in step (0.44.0)

**Goal.** A to-do made into a task (`:Logpose promote`) and the task finish and reopen together,
so an action item doesn't stay open after its task is done.

**Design** (`sync.lua`, `todos.linked`)
- The tie is the `→ [[task]]` line under the to-do (indented under it, before the next item at its
  level). `todos.linked(lines)` finds them; the index stores it on the to-do (`task_link`,
  `task_link_text`).
- Task → to-dos: `taskfile.set_status` (board moves, `:Logpose done`, the form) calls
  `sync.set_todos(root, task, done)` when the status goes in or out of Done. It finds the notes
  with linked to-dos from the index (plus buffers with unsaved changes), resolves only those
  links, and checks or unchecks with `fs.update_lines(…, { raw = true })`: no `modified:` bump,
  and a modified buffer is edited instead of the file.
- To-do → task: `:Logpose check` passes the rows it changed to `sync.todos_changed`. Checked: a
  task at or past `board.start` moves to Done; one before it asks (`vim.ui.select`); "leave it"
  is remembered for the session (`sync.declined`). Unchecked: the task goes back to the column
  before Done, from its `## Log` (`X → Done`), else `board.start`.
- Hand edits: a `BufWritePre` autocmd compares the buffer with the file on disk. A task file whose
  status crossed Done, and linked to-dos whose box changed, are synced after the save. Re-syncing
  what is already in step does nothing, so there are no loops.
- Board undo/redo: after restoring task files, tasks whose Done-ness changed re-sync their
  to-dos (the notes aren't part of the undo snapshot).
- Safety net: `index.build` counts an open linked to-do as checked (`done_by_task`) when its task
  is done, for edits made outside Neovim.
- Carrying over (meeting series, standup Today) copies the `→` line with the to-do, so the new
  copy stays tied; the old one becomes `[>]` and is no longer a to-do.

**Tests** (`test_sync.lua`): done/reopen from `:Logpose done`, the board with undo/redo, `check`
both ways with the column from the log, asking for unstarted tasks, hand edits saved, unsaved
buffers, the index safety net, carrying over.

## C8 — Filter language and lists (0.46.0)

**Goal.** Meetings, notes and people browsed like tasks are on the board: grouped, filtered by
anything in their frontmatter (with `and`, `or`, `not`), and changed by moving them.

**Design: the filter language** (`query.lua`)
- `parse(args, today, lenient)` tokenizes the joined arguments (`(`, `)`, `"quoted text"`) and
  builds an expression: `or` of `and`s of factors; a factor is `not`/`!`, a leading `-`
  (not before a digit, so `-7d` stays a word), `( … )`, or a filter. `and` is implicit (or
  written `and`/`&`); `or`/`|`. Lenient mode skips invalid or half-typed filters and unbalanced
  parentheses; strict mode raises.
- Filters: the old ones (project, tags, `type:`, open/done, since/until, week/sprint, section,
  person/`@`, status, blocked, words) plus any frontmatter field `key:value` (contains, case and
  accents ignored; lists match any element), `key>=v` `>` `<=` `<` (dates and numbers), ranges
  `key:a..b`, `key:*`/`has:key`/`no:key`. Date fields (`date`, `due`, `done`, `created`,
  `started`, `modified`) and date-looking values compare as days; a month or year means its
  whole span (`date<=2026-10` includes the 31st). `attendees:`/`with:` match a person by any of
  their names (`people.expand`) or part of one. `type:` also matches the kind of note
  (`daily`, `meeting`, `topic`, `project`, `task`, `person`).
- Items carry `fields` (the file's frontmatter; a to-do or line, its note's), so fields work in
  every scope. `q` is `{ expr }`; `match`, `filter`.

**Design: lists** (`lists/init.lua`, views `lists/meetings.lua`, `lists/notes.lua`,
`lists/people.lua`; `lists/common.lua` for shared pieces)
- One engine renders a view: entries (`collect`), filtered by project scope and the filter,
  sorted (`sorts`), grouped (`groupings[i].of(e)` → groups; an entry may be in several),
  group headings with every row (0.47.2: no "… N more" rows to expand), `<Tab>` details,
  folding.
- Moving (`m`, `<`, `>`) calls the grouping's `move(s, e, from, to)`, which writes the note
  through `edit.save.note` (a meeting's project moves its file and fixes links; tags and
  `projects` lists swap `from` for `to`). Groupings without `move` (week, month, series, last
  met, page, type of note) refuse with a message. `targets` lists where to go, `ask` adds
  "new…".
- Meetings: by week (default), type, project, series. Notes: topic notes and project pages
  (archived projects' pages left out); daily notes / meetings only when the filter names
  `type:daily` / `type:meeting`; by type, project, tag, month; the date shown is `date:`, else
  `created:`, else the file's time. People: `people.known` entries with a synthesized item
  (text = name, role, aliases; tags = projects; people = slugs; date = last met; fields = the
  page's), by page, project, role, last met; keys `1`, `y`, `o`, `R`.
- They replace the notes screen (`notes/browse.lua`) and the people screen
  (`people/screen.lua`); `K` (peek) moved to `util/peek.lua`, shared with the board.

**Tests** (`test_query.lua`, `test_lists.lua`, `test_lists_people.lua`): the language (or, not,
parentheses, fields, people, dates, ranges, lenient parsing), each list's rows, details,
groupings, filters and moves, projects screen `f`.

## C9 — Discoverable filters, polished lists (0.47.0)

**Goal.** The filter language can be learned while using it, and the lists read at a glance.

**Design**
- `filter/init.lua`: `complete(token, root)` → `{ word, abbr, menu }` for the word being typed:
  filter names with a description (and the frontmatter keys in use), then values by key:
  projects, tags, people (by any part of the name, inserted as handles), meeting types and kinds
  of notes, board columns, sections, field names (`has:`/`no:`), dates with what they mean today
  (`today`, `-7d`, this month, a range), or a field's values in the journal, most used first. A
  leading `-` is kept. `CHEATSHEET` / `cheatsheet_lines()` for help windows. `:Logpose find`
  completion uses it for values.
- `filter/bar.lua`: a one-line float over the list or board window (`relative = "win"`).
  `on_change` re-applies the filter as you type (deferred 40 ms) and returns a count shown on the
  lower edge with the ignored words (lenient `query.parse`'s skipped) and, when empty, examples.
  Our own popup (`vim.fn.complete`, `completeopt=menuone,noinsert,noselect` while open; blink and
  nvim-cmp off in the buffer), re-asked on every change, not re-offered after `<Esc>` closes it
  until the text changes; `<Tab>`, `<CR>` (accept a selected item, else keep the filter), `<Esc>`
  (close the menu, else restore), `<F1>` (cheat sheet). Leaving the window keeps the filter.
- `util/help.lua`: help floats (`open`, `keys(rows)`, `with_filters`) for the lists, the board and
  the projects screen, replacing notifications.
- Lists: the title, scope, filter and "N meetings · by week · newest first · ? help" move to the
  winbar (like the board); groups are `▾ Label  N` (`▸` folded); dates in words (Today,
  Yesterday, Wed 14 Oct); details drawn as a tree (`├`, `└`); empty results say what to do;
  `<BS>` clears the filter (board too).

**Tests**: completion items (`test_lists.lua`), the bar (live list, menu, count, ignored words,
`<Esc>` restores, `<BS>` clears), help windows, the board's bar.

## 5. Command reference (final state)

| Command                                   | Feature |
|-------------------------------------------|---------|
| `:Logpose init [dir]`                     | F1.5 |
| `:Logpose project [name\|none]`           | F1.6 |
| `:Logpose daily [date\|prev\|next\|today]` | F1 |
| `:Logpose meeting [type] [date]`          | F1, F5 |
| `:Logpose archive[!]`                     | F2.1, C1 |
| `:Logpose capture [text]`                 | B1 |
| `:Logpose done`                           | C1 |
| `:Logpose check` (normal / visual)        | C1 |
| `:Logpose find [notes\|daily\|meetings\|topics\|tasks\|todos\|tags\|projects] [filters]` | F4, C1 |
| `:Logpose grep [text]`                    | F4 |
| `:Logpose actions [open\|mine\|overdue\|all] [filters]` | F5 |
| `:Logpose standup [date]`                 | F6 |
| `:Logpose report[!] [week\|sprint] [offset]` | F7 |
| `:Logpose ticket [ID]`                    | F8 |
| `:Logpose find decisions\|blockers\|people …` | O1, O3 |
| `:Logpose note [title]` / `project-page [name]` | O4 |
| `:Logpose backlinks` / `links`            | O4 |
| `:Logpose view [name]`                    | O5 |
| `:Logpose rename-tag` / `rename-project`  | O6 |
| `:Logpose stats[!] [days]`                | T1 |
| `:Logpose board [filters]`                | B1 |
| `:Logpose promote`                        | B1, C1 |
| `:Logpose today`, `edit`, `projects`      | later minors |
| `:Logpose notes [filters]`                | C2, C8 |
| `:Logpose meetings [filters]`             | C8 |
| `:Logpose people [filter]`, `person [handle]`, `rename-person` | C6 |

## 6. Definition of done (every feature)

- Acceptance criteria demonstrated manually in the real journal repo.
- Listed tests written and passing in CI (0.10, stable, nightly).
- `doc/logpose.txt` and README updated (commands, config keys, `<Plug>` mappings).
- `:checkhealth logpose` covers any new requirement the feature introduces.
- Templates and every note logpose generates pass markdownlint's default rules (`make lint-md`,
  run in CI): titles live in the frontmatter only, and writes that create or restructure a note
  go through `markdown.tidy` (blank lines around headings, lists, tables, fences; no blank runs;
  no trailing spaces). User text is never reflowed; only reports wrap their own long items.
- No behaviour change to earlier features unless the spec says so.
- `make lint` passes (StyLua, and `scripts/check-globals.lua`: no global assignments).

### Performance

Measured with `scripts/bench/` on generated journals (2 years ≈ 1,900 files; 5 years ≈ 4,600).
Targets for a 2-year journal, with caches warm: anything that runs while typing (statusline,
completion, resolving the project) under 30 ms; a board action under 100 ms; a screen (today,
projects, standup) under 100 ms. The first command of a session builds the index (≈0.4 s at 2
years).

- **Index**: files are parsed once and cached by mtime (ns) and size; an entry is only trusted
  once it was cached two seconds after the file's mtime (git's "racily clean" rule), so writes
  don't flush the cache: `index.clear_cache()` only bumps `generation`. Within one event-loop
  tick, later builds reuse the last one while `generation` is unchanged (`fs.write_file` and
  saving a markdown buffer bump it), so a command builds the index once.
- **Task files**: `taskfile.list` caches parsed tasks the same way and doesn't walk
  `tasks/archive/` unless archived tasks are asked for (the statusline, the board's refresh and
  its undo snapshots all list tasks).
- 2-year journal, before → after 0.28.2 (warm): board move 730 → 57 ms, undo 530 → 62 ms,
  board refresh 125 → 35 ms, statusline refresh 80 → 4 ms, standup 97 → 42 ms, today 85 → 50 ms.

## 7. Release notes

Per-release changes are in the annotated tags (`git tag -n`). Breaking changes so far:
- 0.48.0: counts work everywhere (`3j`, `2L`, `2>`), so digits are no longer keys: on the
  board `{N}gm` moves a card to column N (was `1`–`9`); on the people list `t` starts a 1:1 (was
  `1`); on the projects screen `x` means no project (was `0`).
- 0.46.0: the notes screen became the notes list (topic notes and project pages; meetings have
  `:Logpose meetings`, daily notes need `type:daily`); on the people list `1` starts a 1:1 (`m`
  moves); highlight groups `LogposeNotes*`/`LogposePeople*` became `LogposeList*`.
- 0.45.0: `:Logpose project none` means no project (nothing detected, picked per note);
  `:Logpose project auto` is what `none` used to do (unpin and detect).
- 0.43.0: `people.md` and `people.file` are gone: people live in `people/<slug>.md` pages;
  `people = { contacts = … }` configures how to reach them.
- 0.26.0: local usage stats are on by default; `telemetry = { enabled = false }` turns them off.
- 0.2.0: default paths are relative to the journal root and the marker is `.logpose`.
- 0.25.0: the board's title line moved into the window's top bar (winbar).
- 0.24.0: `:Logpose` without a subcommand opens the command menu (it used to print usage).
- 0.23.0: board reordering moved from `J`/`K` to `<C-j>`/`<C-k>`; `K` peeks at a card.
- 0.22.0: new notes (daily ones too) start with `created:`/`modified:` frontmatter; task
  `created:` is a date-time.
- 0.21.0: new meeting notes, topic notes, project pages and tasks have no `# Title` heading
  (the frontmatter title is the heading); templates have no `- [ ] ` placeholder lines.
- 0.19.0: `:Logpose find` is live by default with a picker plugin (the filters move into the
  prompt); `search = { live = false }` restores fixed results.

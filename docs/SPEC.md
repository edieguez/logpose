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
0.17.0 = F8, 0.18.0 = T1, 0.19.0 = live search and previews, 0.20.0 = B1, 0.21.0 = markdownlint-clean notes, 0.22.0 = timestamps, board look and delete, 0.23.0 = peek, scrolling columns, WIP limits and age, 0.23.1 = board resize fixes, 0.24.0 = command menu, statusline, board undo, 0.25.0 = today, keymaps preset, titled notifications, board extras); fixes bump the patch;
1.0.0 once M3 is done.

---

## 3. Conventions used across features

**Command surface.** One user command with subcommands and completion:
`:Logpose <subcommand> [args]`. Every subcommand also gets a `<Plug>(logpose-…)` mapping.
No keymaps are set by default; suggested ones go in the README.

**Dates.** ISO `YYYY-MM-DD` strings everywhere; compare them lexicographically. All date
arithmetic goes through `util/date.lua`, anchored at **12:00 local time** to avoid DST bugs.

**Journal files** (default layout, relative to the journal root; every path is configurable via
`dirs`, so an existing journal keeps its own layout in config).
- `INBOX.md` / `DONE.md`: a title, then sections headed `## YYYY-MM-DD`, each holding items.
- Daily notes: `daily/daily-YYYY-MM-DD.md`.
- Meeting notes: `meetings/YYYY-MM-DD - <slug>.md`.
- Week archives: `journal-entries/week-<monday>.md`, `done-entries/done-week-<monday>.md`.

**Tasks.** A task is a markdown list item `- [ ] text` (open) or `- [x] text` (done).
Optional inline metadata, parsed from F5 on: `@owner`, `due:YYYY-MM-DD`.

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
- `:Logpose project [name|none]`: set or clear; no argument → pick from known projects (config
  paths + subdirectories of `meetings/`) or type a new one. Completion lists known projects.
- Meeting notes (F1): saved under `meetings/<project>/` when a project is active; frontmatter
  gains `project: acme`; `{project}` template variable; the series key is project-scoped
  (`acme/retro`) so recurring meetings never mix across projects. The daily-note link is
  prefixed with the project: `- acme: [[meetings/acme/2026-10-14 - retro|Retro]]`.
- `require("logpose").project()` returns the active project (for statuslines).
- Later features use it: F3 capture tags items `#acme`; F4 search, F5 actions and F7 reports
  default to "all", with a `project` argument (`current` = active project).
- Health shows the active project and how it was chosen.
- Project names are slugs (`Acme API` → `acme-api`); `none`, `auto` and `clear` unpin.
- The daily-link duplicate check matches the exact link target, so `retro` in two projects (or
  `retro` vs `retro-2`) are distinct links.

**Acceptance criteria**
- Inside `~/work/acme-api`, `:Logpose meeting retro` creates `meetings/acme-api/<date> - retro.md`
  with `project: acme-api`; the daily note links it under `## Meetings` with the project prefix.
- `:Logpose project thesis` overrides detection until `:Logpose project none`.
- With no project (e.g. editing the journal itself), notes go to `meetings/` as in F1.

**Tests**
- Resolution order (explicit, paths prefix, git, journal repo excluded, none); slugified names;
  subdir and frontmatter; project-scoped series; `meeting_subdir = ""`; completion.

---

## F2 — Archive (Core)

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
- Opt-in: `telemetry = { enabled = true }` (off by default, so other users are never counted
  without knowing); documented in the README and health.
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

**Board** (`board.lua`): `:Logpose board [filters]`
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
  `tasks.promote_status` (TODO) with the note's project and a `From:` link, and turns the line
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

## 5. Command reference (final state)

| Command                                   | Feature |
|-------------------------------------------|---------|
| `:Logpose init [dir]`                     | F1.5 |
| `:Logpose project [name\|none]`           | F1.6 |
| `:Logpose daily [date\|prev\|next\|today]` | F1 |
| `:Logpose meeting [type] [date]`          | F1, F5 |
| `:Logpose archive[!]`                     | F2, F2.1 |
| `:Logpose capture [text]`                 | F3 |
| `:Logpose done` (normal / visual)         | F3 |
| `:Logpose find [notes\|daily\|meetings\|archives\|tasks\|tags\|projects] [filters]` | F4 |
| `:Logpose grep [text]`                    | F4 |
| `:Logpose actions [open\|mine\|overdue\|all] [filters]` | F5 |
| `:Logpose standup [date]`                 | F6 |
| `:Logpose report[!] [week\|sprint] [offset]` | F7 |
| `:Logpose ticket [ID]`                    | F8 |
| `:Logpose find decisions\|blockers\|people …` | O1, O3 |
| `:Logpose triage [filters]`               | O2 |
| `:Logpose note [title]` / `project-page [name]` | O4 |
| `:Logpose backlinks` / `links`            | O4 |
| `:Logpose view [name]`                    | O5 |
| `:Logpose rename-tag` / `rename-project`  | O6 |
| `:Logpose stats[!] [days]`                | T1 |
| `:Logpose board [filters]`                | B1 |
| `:Logpose migrate[!]` / `promote`          | B1 |

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

## 7. Release notes

Per-release changes are in the annotated tags (`git tag -n`). Breaking changes so far:
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

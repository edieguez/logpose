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
| F3 | Kanban flow (capture / done)     | High      | F0         | new                                 |
| F4 | Navigation (pickers)             | High      | F1         | new                                 |
| F5 | Action items & meeting series    | High      | F1, F4*    | new                                 |
| F6 | Standup prep                     | Medium    | F1         | new                                 |
| F7 | Sprints & reports                | Medium    | F1, F2     | new                                 |
| F8 | Ticket references                | Low       | F0, F4*    | new                                 |

\* soft dependency: works with the `vim.ui.select` fallback, better with F4.

**Milestones**
- **M1 (F0–F2, incl. F1.5–F1.6): Core journal.** Onboarding, projects, daily and meeting notes,
  and weekly archiving.
- **M2 (F3–F5): Daily driver.** Capture, complete, find, and follow up on meeting action items.
- **M3 (F6–F8): Scrum layer.** Standup prefill, sprint archives/reports, ticket links.

**Releases.** Annotated tags in `MAJOR.MINOR.PATCH` form (no `v` prefix). Each completed feature
bumps the minor version (0.1.0 = F0+F1, 0.2.0 = F1.5, 0.3.0 = F1.6, 0.4.0 = F2 / M1 …); fixes bump the patch;
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
  archive.lua               -- F2 (+ F7 period hook)
  tasks.lua                 -- F3
  picker/init.lua           -- F4 adapter
  picker/{snacks,fzf_lua,telescope,select}.lua
  actions.lua               -- F5
  standup.lua               -- F6
  period.lua                -- F7 (week/sprint periods)
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
  `{type}`, `{attendees}`, `{series}`, `{previous}`, `{sprint}` (empty until F7).
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
- Later features use it: F3 capture tags items `#acme`; F4 pickers, F5 actions and F7 reports
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
- Grouping goes through a **period function** — `period_of(iso) -> { key, start }` — that
  defaults to "Monday of week". F7 plugs sprints in here without touching the archive logic.
- Jobs: `inbox → journal_entries/<affixes.week><key>.md`, `done → done_entries/<affixes.done_week><key>.md`.
  Date sections in the current (or a future) period stay; preamble and non-date sections stay.
- New archive files start with `archive.journal_title` / `archive.done_title`
  (`# Journal: week of {period}`, `# Done: week of {period}`).
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

## F3 — Kanban flow: capture & done (High)

**Goal.** Get items into INBOX and move finished ones to DONE without leaving the current buffer.

**Design** (`tasks.lua`)
- `:Logpose capture [text]` — no text → `vim.ui.input`. Appends `- [ ] text` under today's
  `## <today>` section in `INBOX.md`, creating the section if missing. **Insert new date sections
  where the existing files put them** (check whether INBOX/DONE are newest-first or oldest-first
  and match it; make it configurable as `section_order` if the two files differ).
- `:Logpose done` (normal mode: current line; visual mode: each task line in range):
  - In `INBOX.md`: remove the line(s), add them as `- [x] …` under today's section in `DONE.md`.
  - In any other journal file (e.g. a meeting note): check it off in place and append it to DONE
    with a link back to the source note.
  - Non-task lines are skipped with a notice.
- Writes to INBOX/DONE follow the §3 rules; edits to the *current* buffer go through the buffer
  API so undo works.

**Acceptance criteria**
- `:Logpose capture Fix flaky test` from a work repo adds the task under today in INBOX.
- `:Logpose done` on an INBOX task moves it to DONE under today; `u` in INBOX restores the line.
- `:Logpose done` on an action item in a meeting note checks it and logs it in DONE with a link.

**Tests**
- Section creation (no section yet / section exists), ordering per `section_order`.
- Visual range with mixed task and non-task lines.
- Back-link generation for both link styles.

---

## F4 — Navigation / pickers (High)

**Goal.** Find any note quickly, with whichever picker the owner has (LazyVim defaults to
snacks.picker or fzf-lua; Telescope is optional).

**Design** (`picker/`)
- Adapter API: `pick_files{ cwd, prompt }`, `grep{ cwd, prompt, default_text }`,
  `pick_items{ items, format, on_choice, prompt }`.
- Backend selection: `config.picker = "auto"` (default: snacks → fzf-lua → telescope →
  select) or a forced name. `select` backend: `pick_files` lists files via `vim.fs.dir`;
  `grep` falls back to `:vimgrep` into quickfix.
- Subcommands: `:Logpose find daily|weekly|meetings|all`, `:Logpose grep [text]`,
  `:Logpose find meetings <type>` (filters by frontmatter `type`; uses `pick_items`).
  `weekly` covers both `journal_entries` and `done_entries`.

**Acceptance criteria**
- Each subcommand works with each installed backend and with the `select` fallback.
- `:Logpose find meetings retro` lists only retro notes, newest first.

**Tests**
- Backend detection order with mocked `package.loaded`.
- Frontmatter type filter on fixture notes (including notes without frontmatter → excluded).
- Picker UIs themselves are verified manually (checklist in the PR).

---

## F5 — Action items & meeting series (High)

**Goal.** Action items from meetings don't get lost, and each recurring meeting starts from the
previous one.

### F5.1 Action items (`:Logpose actions [open|mine|overdue|all]`)
- Scan meeting notes (and daily notes if `actions.include_daily = true`) for tasks.
- Parse `@owner` and `due:YYYY-MM-DD`; `config.me = "@emmanuel"` defines `mine`
  (unassigned items count as mine — configurable).
- Default output is the **quickfix list** (`file:line: text`, sorted by due date, then file date);
  `config.actions.output = "picker"` uses `pick_items`.
- `overdue` = open with `due` < today.
- Completing an item works with F3's `:Logpose done` from the quickfix-opened buffer.

### F5.2 Meeting series
- On meeting creation (F1.3 hook): find the most recent earlier note with the same frontmatter
  `series`. If found:
  - set `{previous}` → link to it (shipped templates render `Previous: {previous}` under the title);
  - add a `## Carried over` section with its **open** tasks, each suffixed with a link to the source.
- `:Logpose meeting` title prompts offer completion from past titles of that type (custom
  completion on `vim.ui.input` where supported; harmless where not).

**Acceptance criteria**
- With two retros containing open items, `:Logpose actions` lists them in quickfix with correct
  lines; `overdue` filters by due date.
- Creating a second `1on1` with the same person links the previous one and carries its open
  follow-ups; a 1:1 with a different person does not.

**Tests**
- Task/metadata parsing: owner, due, both, neither, malformed due.
- Series lookup: picks the most recent earlier note, ignores later dates and other series.
- Carried-over rendering for both link styles.

---

## F6 — Standup prep (Medium)

**Goal.** The daily note arrives with "Yesterday" already written.

**Design** (`standup.lua`, hooked into F1.2 creation only — never modifies an existing note)
- Find the **most recent existing** daily note before the new date (handles weekends, vacations).
- Copy its `## Today` items into the new note's `## Yesterday`.
- Copy its **open** tasks from `## Today` into the new `## Today` (carry-forward), unless
  `standup.carry_forward = false`.
- Optionally append today's DONE entries for that previous date (`standup.include_done = true`).
- Section names configurable: `standup.sections = { yesterday = "Yesterday", today = "Today" }`.
- Add `:Logpose standup` to open a read-only scratch buffer with Yesterday / Today / Blockers of
  today's note, ready to read aloud or paste into chat.

**Acceptance criteria**
- Monday's new note gets Friday's items in "Yesterday"; open Friday tasks carry into "Today".
- An existing daily note is never modified by re-running `:Logpose daily`.

**Tests**
- Previous-note lookup across a gap of several days; no previous note → template unchanged.
- Section extraction when sections are missing, empty, or renamed via config.

---

## F7 — Sprints & reports (Medium)

**Goal.** Archive and report by sprint, not just by calendar week.

**Design**
- `period.lua` config:
  ```lua
  period = {
    kind = "week",                       -- or "sprint"
    week_start = 1,                      -- ISO weekday
    sprint = { anchor = "2026-10-05", length_days = 14, first_number = 1, name = "sprint-{n}" },
  }
  ```
- `period_of(iso)` implements both kinds; F2's archive uses it (sprint files:
  `sprint-<n>.md` / `done-sprint-<n>.md`, prefixes configurable). `{sprint}` template variable
  resolves to the sprint name. Switching from `week` to `sprint` never rewrites existing archives.
- `:Logpose report [week|sprint] [offset]` (offset `0` = current, `-1` = previous) opens a
  markdown scratch buffer with:
  - DONE items in the period (from `DONE.md` and the period's done archive), grouped by date;
  - meetings held in the period (title + link), grouped by type;
  - open action items created in the period (reusing F5).
  `:Logpose report! …` also writes it to `<dirs.reports>/<period key>.md`.

**Acceptance criteria**
- With `kind = "sprint"`, `{sprint}` and archive filenames match the configured calendar.
- `:Logpose report sprint -1` summarises the previous sprint correctly on fixture data.

**Tests**
- `period_of` for weeks with each `week_start`, sprints across anchor and year boundaries, dates
  before the anchor.
- Archive golden cases re-run with sprint periods.
- Report assembly on fixtures.

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

## 5. Command reference (final state)

| Command                                   | Feature |
|-------------------------------------------|---------|
| `:Logpose init [dir]`                     | F1.5 |
| `:Logpose project [name\|none]`           | F1.6 |
| `:Logpose daily [date\|prev\|next\|today]` | F1 |
| `:Logpose meeting [type] [date]`          | F1, F5 |
| `:Logpose archive[!]`                     | F2, F7 |
| `:Logpose capture [text]`                 | F3 |
| `:Logpose done` (normal / visual)         | F3 |
| `:Logpose find daily\|weekly\|meetings [type]\|all` | F4 |
| `:Logpose grep [text]`                    | F4 |
| `:Logpose actions [open\|mine\|overdue\|all]` | F5 |
| `:Logpose standup`                        | F6 |
| `:Logpose report[!] [week\|sprint] [offset]` | F7 |
| `:Logpose ticket [ID]`                    | F8 |

## 6. Definition of done (every feature)

- Acceptance criteria demonstrated manually in the real journal repo.
- Listed tests written and passing in CI (0.10, stable, nightly).
- `doc/logpose.txt` and README updated (commands, config keys, `<Plug>` mappings).
- `:checkhealth logpose` covers any new requirement the feature introduces.
- No behaviour change to earlier features unless the spec says so.

## 7. Release notes

Per-release changes are in the annotated tags (`git tag -n`). Breaking changes so far:
- 0.2.0: default paths are relative to the journal root and the marker is `.logpose`.

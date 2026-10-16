# logpose.nvim

A markdown journal for developers who work in Scrum/Kanban, inside Neovim: daily notes and
standup prep, typed meeting notes with carried-over action items, a Kanban board of task files,
sprint archives and reports, and search across notes, tasks, tags, projects and people.

Everything is plain markdown in a folder you choose. Structure lives in the files themselves
(frontmatter, `## headings`, `#tags`, `@people`, `[[links]]`); logpose reads it, there is no
database.

- [Requirements](#requirements) · [Installation](#installation) · [Getting started](#getting-started)
- [A day with logpose](#a-day-with-logpose) · [Commands](#commands)
- Features: [Daily notes & standup](#daily-notes-and-standup) · [Meetings](#meetings) ·
  [Projects](#projects) · [Tasks & the board](#tasks-and-the-board) ·
  [Search](#search) · [Action items](#action-items) · [People](#people) ·
  [Topic notes & links](#topic-notes-project-pages-and-links) · [Archiving & sprints](#archiving-and-sprints) ·
  [Reports](#reports) · [Tickets](#tickets) · [Saved views](#saved-views) ·
  [Renames](#renaming-tags-and-projects) · [Usage stats](#usage-stats)
- [Templates](#templates) · [Configuration](#configuration) · [Journal layout](#journal-layout) ·
  [Keymaps](#keymaps) · [Health](#health) · [Development](#development)

## Requirements

- Neovim 0.10+
- Optional picker: [snacks.nvim](https://github.com/folke/snacks.nvim) (LazyVim's default),
  [fzf-lua](https://github.com/ibhagwan/fzf-lua) or
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim). Without one, logpose uses
  `vim.ui.select` and the quickfix list.
- Optional completion: [blink.cmp](https://github.com/Saghen/blink.cmp) or
  [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) for `[[` note links.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "edieguez/logpose",
  cmd = "Logpose",
  ft = "markdown", -- for `gx` on tickets and [[ completion in journal notes
  opts = {},
}
```

For local development, use `dir = "~/Projects/logpose"` instead of the repo name.

## Getting started

Run `:Logpose init` and pick a directory (default `~/journal`). Logpose creates `daily/`,
`meetings/`, `tasks/` and a `.logpose` marker, and remembers the folder, so every
command works from any buffer with no configuration. Pointing it at a folder that already has
notes only adds the marker. Skip this step and the first command that needs a journal offers to
create one, then carries on. Run `:Logpose init` again to switch journals.

Then run `:checkhealth logpose` to see the journal root, the active project, the archive period
and the picker in use.

## A day with logpose

```vim
:Logpose daily              " today's note: yesterday's done items and open tasks already in place
:Logpose standup            " Yesterday / Today / Blockers, grouped by project, for the daily meeting
:Logpose meeting retro      " meeting note for the active project; last retro's open items carried over
:Logpose capture Fix flaky test        " → a task file in Backlog, for the active project
:Logpose board              " what's pending: L moves a card right, x finishes it, <CR> opens it
:Logpose promote            " on a meeting action item: make it a task with its own context
:Logpose actions overdue    " what's slipping
:Logpose report sprint -1   " sprint review / retro prep
:Logpose archive            " file away last sprint's done tasks
```

## Commands

Every command is a subcommand of `:Logpose` with `<Tab>` completion, and has a
`<Plug>(logpose-<name>)` mapping. A bang can go on either side: `:Logpose archive!` = `:Logpose! archive`.

| Command | What it does |
|---|---|
| `init [dir]` | Choose or create the journal folder and remember it. |
| `daily [today\|prev\|next\|DATE]` | Create (from the previous note) and open a daily note. `prev`/`next` step by workdays. |
| `standup [DATE]` | Yesterday / Today / Blockers of the daily note in a scratch buffer, grouped by project. |
| `meeting [type] [DATE]` | New meeting note (picker without a type). `DATE` backfills. |
| `project [name\|none]` | Pin the active project, or go back to auto-detection. |
| `board [filters]` | The Kanban board of task files. |
| `capture[!] [text]` | New task file in Backlog for the active project (`!` opens it). |
| `done` | In a task file: move it to Done. On checkboxes: check them off. |
| `promote` | Turn the checkbox under the cursor into a task file it links to. |
| `migrate[!]` | Turn open INBOX items into task files (preview first). |
| `triage [filters]` | Open the board on Backlog. |
| `find [scope] [filters]` | Search notes, tasks, decisions, blockers, tags, projects, people. |
| `grep [text]` | Live grep in the journal. |
| `view [name]` | Run a saved search. |
| `actions [open\|mine\|overdue\|all] [filters]` | Meeting action items in the quickfix list. |
| `note [title]` | Create/open a topic note in `notes/`. |
| `project-page [name]` | Create/open a project page in `projects/`. |
| `backlinks` / `links` | Notes linking to the current one / links going out of it. |
| `archive[!]` | File away done tasks (and INBOX/DONE sections) from past weeks or sprints. |
| `report[!] [week\|sprint] [offset] [filters]` | Week or sprint summary with a review section (`!` saves it). |
| `ticket [ID]` | Every line mentioning a ticket (default: the one under the cursor). |
| `rename-tag[!] old new` | Rename a tag everywhere (preview first). |
| `rename-project[!] old new` | Rename a project: frontmatter, tags, meeting folder, project page, links. |
| `stats[!] [days]` | Local usage stats (when enabled); `!` resets them. |

## Daily notes and standup

`:Logpose daily` opens today's note, creating it from the `daily` template. A new note starts
from your most recent earlier note (Friday's on a Monday):

- tasks you checked off under `## Today` are listed under `## Yesterday` (other lines are copied
  as they are),
- unfinished tasks move to the new `## Today` and are marked `- [>]` (migrated) in the old note,
  so they're tracked once,
- with `standup = { include_done = true }`, Yesterday also lists that day's DONE entries.

Existing notes are never changed. `:Logpose standup` then shows Yesterday / Today / Blockers in a
scratch buffer, grouped by project tag (`### acme`, `### thesis`, `### other`), ready to read out.
The board feeds it too: tasks finished since the previous workday go under Yesterday, tasks In
progress under Today, and blocked tasks (with the reason) under Blockers.

Section names are configurable (`standup.sections = { yesterday = "Ayer", today = "Hoy", blockers = "Bloqueos" }`).

## Meetings

`:Logpose meeting [type]` creates a note from the type's template, with YAML frontmatter, and
links it under `## Meetings` in that day's daily note. Types:

| Type | Asks for | Title |
|---|---|---|
| `planning`, `refinement`, `review`, `retro` | nothing | fixed |
| `1on1` | the person (with completion) | `1:1 <person>` |
| `adhoc` | a title (with completion of past titles) | as typed |

Add your own in `meeting_types` (`standup = { label = "Standup", title = "Standup" }`), remove one (`retro = false`),
or set `ask_attendees = true` on a type to be asked for attendees. Accented titles are
transliterated in filenames (`Reunión con QA` → `2026-10-14 - reunion-con-qa.md`); the note keeps
the original title. Same type and title on the same day opens the existing note (add `{time}` to
`meeting_filename` to allow several).

**Series.** Meetings with the same type and title (or the same person for 1:1s), within a
project, form a series. A new note in a series starts with `Previous: [[…]]` and a
`## Carried over` section holding the previous note's open tasks; those are marked `- [>]` in
the old note. Turn off with `series = { carry_over = false }` or `{ mark_carried = false }`.

## Projects

One journal holds several unrelated projects. The active project is, in order: the one pinned
with `:Logpose project <name>`, a `projects.paths` match, the git repo of the current buffer
(`~/work/Acme API` → `acme-api`), or none. Inside the journal there is no project.

With a project, meeting notes go to `meetings/<project>/` with `project:` in the frontmatter,
the daily-note link is prefixed (`- acme-api: [[…|Retro]]`), captures get `#acme-api`, and
series never mix across projects. `meeting_subdir = ""` keeps all meetings in one folder.
`require("logpose").project()` returns the active project, e.g. for your statusline.

## Tasks and the board

Every task is a markdown file in `tasks/`, so it can hold the context a one-line checkbox can't:
links, notes, a checklist, decisions. The frontmatter tracks where it is:

```markdown
---
title: "Fix flaky test"
status: in-progress
project: acme
tags: [perf]
due: 2026-10-20
blocked: waiting on ana
created: 2026-10-15T09:05
modified: 2026-10-16T15:02
started: 2026-10-16
done:
---
## Context

Fails on Mondays only; see [[meetings/acme/2026-10-14 - retro|Retro]].

## Log

- 2026-10-15 09:05: created in Backlog
- 2026-10-16 09:10: TODO → In progress
- 2026-10-16 15:02: blocked: waiting on ana
```

You never edit `status` by hand: logpose moves it, sets `started` and `done`, and appends to
the `## Log`.

**The board.** `:Logpose board [filters]` shows the tasks as columns:
**Backlog → TODO → In progress → Follow-up → Done**. Each card is a box with the title,
`⊘ reason` when blocked (red border), and `◆ project #tags ◷ MM-DD` (overdue dates in red).
The focused card gets a heavy border. Each column has its own colour: grey, blue, yellow,
purple, green by default, linked to your colour scheme's diagnostic groups; set a column's `hl`
to another highlight group, or override the `LogposeBoard*` groups (`LogposeBoardColumn1`…,
`LogposeBoardFocus`, `LogposeBoardBlocked`, `LogposeBoardOverdue`, `LogposeBoardProject`,
`LogposeBoardTag`…). In a project's repo you see that project's tasks; inside the journal, all
of them.

| Key | Action | Key | Action |
|---|---|---|---|
| `h` `l` | previous / next column | `j` `k` | previous / next card |
| `H` `L` (`<` `>`) | move the card left / right | `1`–`9` | move it to column N |
| `x` | done | `b` | block (asks why) / unblock |
| `<C-j>` `<C-k>` | move the card down / up | `a` | add a card to this column |
| `K` | peek: the task in a floating window | `D` | delete the card (asks first) |
| `z` | fold / unfold the column | `gg` `G` | first / last card |
| `<CR>` | open the task file | `/` | filter (`find` filters) |
| `p` | this project / all | `r` `q` `?` | refresh, close, help |

Each card shows how long it has been in its column (`4d`, from its log); cards untouched for
`board.stale_days` (7) fade, so forgotten work stands out. A column with a `limit` shows
`In progress (2/3)` and turns the count red above it (In progress has a limit of 3 by default).
Columns scroll on their own (`↑ 3 more` / `↓ 5 more`), keeping the focused card in view, and
`z` folds a column to a narrow strip with its count (`board.collapsed = { "done" }` starts it
folded). `K` opens the task in a floating window to read or edit its context without leaving
the board; `q` closes it, saves, and the board picks up the change.

The cursor and the mouse select cards too. Coming back to the board (`<C-o>`, `:b#`) redraws
it. Done shows what finished in the current week or sprint; older done tasks are filed away
by `:Logpose archive`. Narrow windows stack the columns vertically.

**Getting tasks in.**
- `:Logpose capture fix flaky test #perf due:2026-10-20` creates a Backlog task from anywhere,
  for the active project; tags and `due:` go into the frontmatter. `capture!` opens it.
- `a` on the board adds a card to the focused column.
- `:Logpose promote` on a checkbox in a meeting or daily note creates a TODO task with the
  note's project and a `From:` link back, and turns the line into a link to the task.
- `:Logpose migrate` turns your open INBOX.md items into task files (indented lines under an
  item become its body; `## Someday` items get `#someday`), then removes them from INBOX.
  DONE.md stays as history.

**Getting tasks out.** On the board `L`/`x`; in a task file, `:Logpose done`. Small
checkboxes inside notes still work: `:Logpose done` checks them off.

Columns are configurable (`board.columns`), and so are the columns that set `started` and
`done` (`board.start`, `board.done`). Prefer the old single-file flow? `tasks = { mode = "inbox" }`
brings back INBOX.md/DONE.md for `capture`, `done` and the one-item-at-a-time `triage`.

Files with unsaved changes are never overwritten: logpose edits the buffer instead, or refuses.

## Search

`:Logpose find [scope] [filters…]` searches an index of every note, task and tagged line, and
opens the result at its line. Every picker shows the same results, with a preview of the file
at that line.

**Live search.** With snacks.nvim, fzf-lua or Telescope, the picker prompt *is* the query: it
starts with the filters you typed on the command line, and the results update as you edit
it, so `:Logpose find tasks` then typing `#perf open flaky` narrows step by step. Half-typed
filters (`project:`, `since:2026-1`) are ignored until they're complete. In snacks, `<C-g>`
switches to fuzzy-matching the current results. Set `search = { live = false }` to get fixed
results that the picker fuzzy-filters instead. In `tags`, `projects` and `people`, the
preview shows what each entry leads to.


Scopes: `notes` (default), `daily`, `meetings`, `topics`, `archives`, `tasks`, `decisions`,
`blockers`, `tags` (pick a tag, then everything carrying it), `projects`, `people`.

| Filter | Matches |
|---|---|
| `project:acme` | items of the project, or tagged `#acme` |
| `#perf` / `tag:perf` | tagged items |
| `person:ana` / `@ana` | items involving the person (attendee, 1:1, @mention) |
| `type:retro` | meetings of that type |
| `open` / `done` | tasks by state (checkboxes and task files) |
| `status:in-progress` / `blocked` | task files by column; blocked ones |
| `since:DATE` / `until:DATE` | `YYYY-MM-DD`, `today`, `yesterday`, `-7d`, `+2w` |
| `week:current` / `sprint:-1` / `sprint:42` | a whole week or sprint |
| `section:decisions` | lines under a matching `## ` heading |
| other words | must all appear in the text |

```vim
:Logpose find decisions project:acme sprint:current
:Logpose find tasks open #perf
:Logpose find people
```

Every line under `## Decisions`, `## Blockers`, `## Risks` and `## Open questions` is searchable,
tagged or not (`retrieval.sections`). Tags are inline `#words` (not headings, URL fragments or
`#123`) plus frontmatter `tags: [a, b]`, compared case-insensitively. `:Logpose grep [text]`
runs the picker's live grep in the journal (quickfix list without a picker).

## Action items

Write action items as tasks, optionally with an owner and a due date:
`- [ ] fix CI @ana due:2026-10-20`.

`:Logpose actions [open|mine|overdue|all] [filters]` lists them from all meeting notes in the
quickfix list (or the picker with `actions.output = "picker"`), soonest due first, overdue ones
flagged. `mine` uses `me = "@yourname"` plus unassigned items; filters work as in `find`:
`:Logpose actions overdue project:acme since:-14d`.

## People

People come from meeting `attendees:`, the person of a 1:1 (`with:`) and `@mentions`.
`:Logpose find people` lists everyone with how many notes and items involve them; pick one to
see all of it. `person:ana` / `@ana` filter any search, and `:Logpose actions person:ana` lists
her action items.

## Topic notes, project pages and links

- `:Logpose note [title]` creates or opens `notes/<slug>.md` for knowledge that isn't tied to a
  day: how-tos, decision records, references.
- `:Logpose project-page [name]` creates or opens `projects/<name>.md` (overview, links,
  decisions, open questions), the hub for a project. Without a name it uses the active project.
- `:Logpose backlinks` lists the notes and lines linking to the current note; `:Logpose links`
  lists its outgoing links (missing targets flagged). Wiki links (`[[target|label]]`, also short
  `[[name]]`) and relative markdown links are understood.
- Typing `[[` offers every note as a completion and inserts a link in your `link_style`:
  - **blink.cmp**: add `logpose = { name = "logpose", module = "logpose.completion.blink" }` to
    `sources.providers` and `"logpose"` to your markdown sources.
  - **nvim-cmp**: registered automatically by `setup()`; add `{ name = "logpose" }` to your
    markdown sources.

## Archiving and sprints

`:Logpose archive` files away everything from before the current period: done task files move
to `tasks/archive/<period>/` (reports still count them), and, if you have them, `INBOX.md` /
`DONE.md` sections move into `journal-entries/` and `done-entries/`, one file per period,
merging into files that already exist. It shows a preview and asks first; running it again is
always safe.

Periods are Monday weeks by default. For sprints, give logpose the start date of any one sprint
and its number; e.g. two-week sprints running Thursday to Wednesday:

```lua
period = {
  kind = "sprint",
  sprint = { anchor = "2026-10-01", length_days = 14, first_number = 42 },
},
```

Sprints are counted from the anchor in both directions, archives become `sprint-42.md` /
`done-sprint-42.md`, and `{sprint}` works in templates (whenever an anchor is set). To keep
weekly archives aligned with Thursday sprints instead, use `period = { week_start = 4 }`.

## Reports

`:Logpose report [week|sprint] [offset] [filters]` summarises a period (default: the current one
of your configured kind; `-1` is the previous, a date picks the period containing it) in a
scratch buffer: tasks done by date, meetings by type, decisions, and open action items. A
**review** section lists what needs attention now: overdue actions per project, blocked tasks,
tasks in progress for longer than `review.stale_days`, stale open checkboxes, and (if you
still use INBOX.md) INBOX items from before the period or without a project. Filters limit it, e.g. `:Logpose report sprint -1 project:acme`. `report!` saves it to
`reports/<period>.md`.

## Tickets

With `tickets = { url = "https://acme.atlassian.net/browse/{id}" }`, `gx` on `PROJ-123` in a
journal note opens it (other `gx` uses work as usual). `:Logpose ticket [ID]` lists every line in
the journal mentioning a ticket (whole word; default: the one under the cursor). The ID pattern
is configurable (`tickets.pattern`, a Lua pattern).

## Saved views

```lua
views = {
  acme = "tasks open project:acme",
  decisions = "decisions sprint:current",
},
```

`:Logpose view acme` runs `:Logpose find tasks open project:acme`; `:Logpose view` picks one.

## Renaming tags and projects

- `:Logpose rename-tag perf performance` renames inline `#perf` tags and frontmatter `tags:`
  entries everywhere (not `#perfect`).
- `:Logpose rename-project acme acme-web` updates `project:` frontmatter, `#acme` tags and series
  names, moves `meetings/acme/` and `projects/acme.md`, and fixes links pointing into them.

Both show a preview and ask first (`!` skips it) and never touch files with unsaved changes.

## Usage stats

Opt-in and strictly local: `telemetry = { enabled = true }` counts which commands you use per
day in `stdpath("data")/logpose/usage.json` (only the command and, for `find`, `actions`,
`report` and `daily`, the scope/mode keyword; never note content, paths or arguments).
`:Logpose stats [days]` shows uses per command, the last 7 days vs the previous 7, errors, and
the commands you haven't used. `:Logpose stats!` resets. Days older than
`telemetry.retention_days` are dropped.

## Templates

Shipped templates: `daily`, `meeting`, `planning`, `refinement`, `review`, `retro`, `1on1`,
`note`, `project`, `task`. Put a file with the same name in your journal's `templates/` folder to
override one. Variables: `{date}`, `{time}`, `{weekday}`, `{iso_week}`, `{sprint}`, `{title}`,
`{type}`, `{type_label}`, `{series}`, `{attendees}`, `{project}`. `{cursor}` marks where the
cursor lands. Unknown variables are left as they are.

New notes get `created:` and `modified:` in their frontmatter (local time, ISO 8601:
`2026-10-15T18:57`; daily notes get a small frontmatter for them). `modified:` is bumped
whenever logpose changes a note and whenever you save one you changed in Neovim; notes without
a `modified:` key (older ones) are left alone, so add the key to opt one in. Turn either off
with `timestamps = { created = false, modified = false }`.

Every note logpose creates passes markdownlint's default rules. Meeting notes, topic notes,
project pages and tasks carry their title in the frontmatter, which markdownlint counts as the
top-level heading, so their body starts at `##` (a `# Title` as well would break MD025, one
top-level heading per document). When logpose creates or reorganizes a note (a meeting link
in the daily note, a carried-over item, a log line, an INBOX section) it also keeps the blank
lines markdownlint asks for around headings, lists, tables and code blocks; it never rewraps
what you wrote, so long lines (MD013) are up to you. Your own templates get the same blank-line
treatment.

## Configuration

`setup()` is optional. Defaults:

```lua
require("logpose").setup({
  root = nil,                            -- journal path; overrides the one saved by :Logpose init
  root_markers = { ".logpose" },
  dirs = {                               -- relative to the root
    daily = "daily", meetings = "meetings", notes = "notes", projects = "projects", tasks = "tasks",
    inbox = "INBOX.md", done = "DONE.md",
    journal_entries = "journal-entries", done_entries = "done-entries",
    templates = "templates", reports = "reports",
  },
  affixes = { daily = "daily-", week = "week-", done_week = "done-week-", sprint = "", done_sprint = "done-" },
  link_style = "wiki",                   -- or "markdown"
  link_base = "",                        -- wiki-link targets are relative to this dir ("" = root)
  workdays = { 1, 2, 3, 4, 5 },          -- ISO weekdays, Monday = 1
  picker = "auto",                       -- "snacks" | "fzf_lua" | "telescope" | "select"
  meeting_filename = "{date} - {slug}",  -- may add {time} (HHMM)
  meeting_subdir = "{project}",          -- "" keeps all meetings in one folder
  meeting_types = {
    planning   = { label = "Sprint planning", template = "planning", title = "Sprint planning", order = 10 },
    refinement = { label = "Refinement", template = "refinement", title = "Refinement", order = 20 },
    review     = { label = "Sprint review", template = "review", title = "Sprint review", order = 30 },
    retro      = { label = "Retrospective", template = "retro", title = "Retro", order = 40 },
    ["1on1"]   = { label = "1:1", template = "1on1", prompt = "Person: ", title = "1:1 {input}", person = true, order = 50 },
    adhoc      = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
    -- per type also: ask_attendees = true
  },
  section_order = "auto",                -- "newest_first" | "oldest_first"
  archive = { journal_title = "# Journal: {period_label}", done_title = "# Done: {period_label}" },
  period = {
    kind = "week",                       -- or "sprint"
    week_start = 1,
    sprint = { anchor = nil, length_days = 14, first_number = 1, name = "sprint-{n}" },
  },
  me = nil,                              -- "@yourname"
  actions = { include_daily = false, unassigned_mine = true, output = "quickfix" },
  series = { carry_over = true, mark_carried = true },
  standup = {
    sections = { yesterday = "Yesterday", today = "Today", blockers = "Blockers" },
    carry_forward = true, mark_carried = true, include_done = false, group_by_project = true,
  },
  review = { stale_days = 14 },
  tickets = { pattern = "%u[%u%d]+%-%d+", url = nil },
  telemetry = { enabled = false, retention_days = 180 },
  views = {},
  tasks = {
    mode = "files",                      -- or "inbox": the INBOX.md/DONE.md checkbox flow
    capture_status = "backlog",          -- column for :Logpose capture
    promote_status = "todo",             -- column for :Logpose promote
  },
  board = {
    columns = {
      { key = "backlog", label = "Backlog" },
      { key = "todo", label = "TODO" },
      { key = "in-progress", label = "In progress", limit = 3 },   -- also: hl = "…"
      { key = "follow-up", label = "Follow-up" },
      { key = "done", label = "Done" },
    },
    start = "in-progress",               -- reaching it sets `started:`
    done = "done",                       -- reaching it sets `done:`
    done_window = "period",              -- Done shows this week/sprint, or a number of days
    min_column_width = 24,               -- narrower than this, columns stack
    stale_days = 7,                      -- cards this long in a column fade
    collapsed = {},                      -- columns folded when the board opens
  },
  timestamps = {
    created = true,                      -- `created:` in new notes (local time, 2026-10-15T18:57)
    modified = true,                     -- `modified:`, bumped on every change
  },
  search = { live = true },              -- the picker prompt re-runs the query as you type
  retrieval = { sections = { "decisions", "blockers", "risks", "open questions" } },
  projects = {
    detect = true,                       -- the git repo you're in is the project
    paths = {},                          -- { ["~/work/acme-api"] = "acme" }; longest match wins
  },
})
```

Unknown options produce a warning; invalid values an error. Lists are replaced, not merged.

An existing journal with a different layout just needs `dirs` (and `link_base` if wiki links
should be relative to a subfolder):

```lua
opts = {
  root = "~/repos/my-journal",
  link_base = "journal",
  dirs = {
    daily = "journal/daily", meetings = "journal/meetings", inbox = "journal/INBOX.md",
    done = "journal/DONE.md", journal_entries = "journal/journal-entries",
    done_entries = "journal/done-entries", templates = "journal/templates",
  },
}
```

The journal root is resolved in this order: `root` → a marker above the current buffer → a marker
above the current directory → the journal saved by `:Logpose init`.

## Journal layout

```
~/journal/
├── .logpose
├── tasks/
│   ├── fix-flaky-test.md     # one file per task
│   └── archive/sprint-42/    # done tasks of past periods
├── daily/daily-2026-10-14.md
├── meetings/
│   ├── acme-api/2026-10-14 - retro.md
│   └── 2026-10-13 - 1-1-ana.md
├── notes/queue-design.md
├── projects/acme-api.md
├── journal-entries/sprint-42.md
├── done-entries/done-sprint-42.md
├── reports/sprint-42.md
└── templates/                # your overrides
```

Checkboxes in notes: `- [ ]` open, `- [x]` done, `- [>]` migrated (carried to a newer note).
With `tasks = { mode = "inbox" }`, `INBOX.md` and `DONE.md` hold `## YYYY-MM-DD` sections of
checkboxes instead of `tasks/`.

## Keymaps

None are set by default. For example:

```lua
local map = vim.keymap.set
map("n", "<leader>jd", "<Plug>(logpose-daily)", { desc = "Daily note" })
map("n", "<leader>js", "<Plug>(logpose-standup)", { desc = "Standup" })
map("n", "<leader>jm", "<Plug>(logpose-meeting)", { desc = "Meeting note" })
map("n", "<leader>jk", "<Plug>(logpose-board)", { desc = "Board" })
map("n", "<leader>jc", "<Plug>(logpose-capture)", { desc = "Capture a task" })
map({ "n", "x" }, "<leader>jx", "<Plug>(logpose-done)", { desc = "Mark done" })
map("n", "<leader>jp", "<Plug>(logpose-promote)", { desc = "Promote to task file" })
map("n", "<leader>jf", "<Plug>(logpose-find)", { desc = "Find notes" })
map("n", "<leader>jt", "<cmd>Logpose find tasks open<cr>", { desc = "Open tasks" })
map("n", "<leader>ja", "<Plug>(logpose-actions)", { desc = "Action items" })
map("n", "<leader>jb", "<Plug>(logpose-backlinks)", { desc = "Backlinks" })
map("n", "<leader>j/", "<Plug>(logpose-grep)", { desc = "Grep journal" })
```

## Health

`:checkhealth logpose` reports the Neovim version, the journal root and how it was found, the
active project, the archive period (current week or sprint), which journal paths exist, the
picker in use and whether usage stats are on.

## Development

```sh
make test                              # full suite (clones mini.nvim into deps/ on first run)
make test-file FILE=tests/test_date.lua
make lint                              # stylua --check
make lint-md                           # markdownlint on the templates and generated notes
make format
```

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md),
each case in a fresh child Neovim with its own data folder, and run with
`TZ=America/New_York` so date math crosses real DST changes. CI runs Neovim 0.10, stable and
nightly. The full design and roadmap are in [`docs/SPEC.md`](docs/SPEC.md); releases are tagged
`MAJOR.MINOR.PATCH` (`git tag -n` lists what each one added).

## License

Apache 2.0

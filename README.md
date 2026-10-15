# logpose.nvim

A markdown journal for developers who work in Scrum/Kanban, inside Neovim: daily notes and
standup prep, typed meeting notes with carried-over action items, an INBOX/DONE Kanban flow,
sprint archives and reports, and search across notes, tasks, tags, projects and people.

Everything is plain markdown in a folder you choose. Structure lives in the files themselves
(frontmatter, `## headings`, `#tags`, `@people`, `[[links]]`); logpose reads it, there is no
database.

- [Requirements](#requirements) · [Installation](#installation) · [Getting started](#getting-started)
- [A day with logpose](#a-day-with-logpose) · [Commands](#commands)
- Features: [Daily notes & standup](#daily-notes-and-standup) · [Meetings](#meetings) ·
  [Projects](#projects) · [Capture, done, triage](#capture-done-and-triage) ·
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
`meetings/`, `INBOX.md`, `DONE.md` and a `.logpose` marker, and remembers the folder, so every
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
:Logpose capture Fix flaky test        " → INBOX, tagged #project
:Logpose done               " on a task: INBOX → DONE, or check off a meeting action item
:Logpose triage             " end of day: give every INBOX item a home
:Logpose actions overdue    " what's slipping
:Logpose report sprint -1   " sprint review / retro prep
:Logpose archive            " move past sprints out of INBOX and DONE
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
| `capture [text]` | Add `- [ ] text` under today in INBOX, tagged with the active project. |
| `done` | Mark the task on the line / range / visual selection done. |
| `triage [filters]` | Process open INBOX items one at a time. |
| `find [scope] [filters]` | Search notes, tasks, decisions, blockers, tags, projects, people. |
| `grep [text]` | Live grep in the journal. |
| `view [name]` | Run a saved search. |
| `actions [open\|mine\|overdue\|all] [filters]` | Meeting action items in the quickfix list. |
| `note [title]` | Create/open a topic note in `notes/`. |
| `project-page [name]` | Create/open a project page in `projects/`. |
| `backlinks` / `links` | Notes linking to the current one / links going out of it. |
| `archive[!]` | Move past weeks or sprints out of INBOX and DONE (preview first; `!` skips it). |
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

## Capture, done and triage

- `:Logpose capture [text]` adds `- [ ] text` under today's `## YYYY-MM-DD` section in INBOX
  (created as needed, in the file's date order), from any buffer.
- `:Logpose done` works on the current line, a `:range` or a visual selection
  (`<Plug>(logpose-done)`). In INBOX the task moves to today's section in DONE; in any other note
  it's checked off in place and logged in DONE with a link back. `u` undoes the edit.
- `:Logpose triage [filters]` walks open INBOX tasks, oldest first. For each: `project`, `tag`,
  `due` (`+3d`, `tomorrow`…), `owner` (these keep the item on screen), `move` (into a note's
  `## Action items` or `## Notes`), `done`, `someday` (parked under `## Someday`), `drop`
  (confirmed once per session), `skip`, `quit`.

Files with unsaved changes are never overwritten: logpose edits the buffer instead, or refuses.

## Search

`:Logpose find [scope] [filters…]` searches an index of every note, task and tagged line, and
opens the result at its line. Every picker shows the same results.

Scopes: `notes` (default), `daily`, `meetings`, `topics`, `archives`, `tasks`, `decisions`,
`blockers`, `tags` (pick a tag, then everything carrying it), `projects`, `people`.

| Filter | Matches |
|---|---|
| `project:acme` | items of the project, or tagged `#acme` |
| `#perf` / `tag:perf` | tagged items |
| `person:ana` / `@ana` | items involving the person (attendee, 1:1, @mention) |
| `type:retro` | meetings of that type |
| `open` / `done` | tasks by state |
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

`INBOX.md` and `DONE.md` hold `## YYYY-MM-DD` sections. `:Logpose archive` moves every section
from before the current period into `journal-entries/` (from INBOX) and `done-entries/` (from
DONE), one file per period, merging into files that already exist. Current sections, the title
and non-date sections (`## Someday`) stay. It shows a preview and asks first; running it again is
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
scratch buffer: DONE items by date, meetings by type, decisions, and open action items. A
**review** section lists what needs attention now: overdue actions per project, stale open tasks
(older than `review.stale_days`), INBOX items from before the period, and INBOX items without a
project. Filters limit it, e.g. `:Logpose report sprint -1 project:acme`. `report!` saves it to
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
`note`, `project`. Put a file with the same name in your journal's `templates/` folder to
override one. Variables: `{date}`, `{time}`, `{weekday}`, `{iso_week}`, `{sprint}`, `{title}`,
`{type}`, `{type_label}`, `{series}`, `{attendees}`, `{project}`. `{cursor}` marks where the
cursor lands. Unknown variables are left as they are.

## Configuration

`setup()` is optional. Defaults:

```lua
require("logpose").setup({
  root = nil,                            -- journal path; overrides the one saved by :Logpose init
  root_markers = { ".logpose" },
  dirs = {                               -- relative to the root
    daily = "daily", meetings = "meetings", notes = "notes", projects = "projects",
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
├── INBOX.md                  # ## YYYY-MM-DD sections of - [ ] tasks, ## Someday
├── DONE.md                   # ## YYYY-MM-DD sections of - [x] tasks
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

Task states: `- [ ]` open, `- [x]` done, `- [>]` migrated (carried to a newer note).

## Keymaps

None are set by default. For example:

```lua
local map = vim.keymap.set
map("n", "<leader>jd", "<Plug>(logpose-daily)", { desc = "Daily note" })
map("n", "<leader>js", "<Plug>(logpose-standup)", { desc = "Standup" })
map("n", "<leader>jm", "<Plug>(logpose-meeting)", { desc = "Meeting note" })
map("n", "<leader>jc", "<Plug>(logpose-capture)", { desc = "Capture to INBOX" })
map({ "n", "x" }, "<leader>jx", "<Plug>(logpose-done)", { desc = "Mark done" })
map("n", "<leader>ji", "<Plug>(logpose-triage)", { desc = "Triage INBOX" })
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
make format
```

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md),
each case in a fresh child Neovim with its own data folder, and run with
`TZ=America/New_York` so date math crosses real DST changes. CI runs Neovim 0.10, stable and
nightly. The full design and roadmap are in [`docs/SPEC.md`](docs/SPEC.md); releases are tagged
`MAJOR.MINOR.PATCH` (`git tag -n` lists what each one added).

## License

Apache 2.0

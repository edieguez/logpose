# logpose.nvim

Daily notes, meeting notes and sprint archives for Scrum/Kanban developers, in Neovim.

> **Status: early development.** The core journal (M1) is done: onboarding, projects, daily and
> meeting notes, and weekly or sprint archiving. M2 is under way: capture/done and search work;
> meeting action items land next.
> See [`docs/SPEC.md`](docs/SPEC.md) for the full plan and roadmap.

## Requirements

- Neovim 0.10+
- Optional picker: [snacks.nvim](https://github.com/folke/snacks.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua)
  or [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (falls back to `vim.ui.select`)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "edieguez/logpose",
  cmd = "Logpose",
  opts = {},
}
```

For local development, use `dir = "~/Projects/logpose"` instead of the repo name.

## Getting started

Run `:Logpose init` and pick a directory for your journal (default `~/journal`). Logpose creates
it with `daily/`, `meetings/`, `INBOX.md`, `DONE.md` and a `.logpose` marker, and remembers it, so
commands work from any buffer with no configuration. Pointing it at a directory that already has
notes only adds the marker.

If you skip this step, the first command that needs a journal offers to create one and then
carries on. Run `:Logpose init` again any time to switch journals.

## Usage

| Command | What it does |
|---|---|
| `:Logpose init [dir]` | Choose or create the journal directory and remember it. |
| `:Logpose project [name\|none]` | Pin the active project (or `none` to go back to auto-detection). No argument: pick from a list. |
| `:Logpose archive[!]` | Move past weeks of `INBOX.md`/`DONE.md` into weekly archive files. Shows a preview and asks first; `!` skips it. |
| `:Logpose capture [text]` | Add `- [ ] text` under today in `INBOX.md` (tagged `#project` when one is active). No text: prompt. |
| `:Logpose done` | Mark the task on the current line (or a range / visual selection) done: from INBOX it moves to `DONE.md`; in a meeting or daily note it's checked off and logged in DONE with a link. |
| `:Logpose find [scope] [filters]` | Search notes, tasks, tags and projects (see below). |
| `:Logpose grep [text]` | Live grep in the journal (quickfix list without a picker plugin). |
| `:Logpose daily [today\|prev\|next\|YYYY-MM-DD]` | Create (if needed) and open a daily note. `prev`/`next` step by workdays from the note you're in. |
| `:Logpose meeting [type] [YYYY-MM-DD]` | New meeting note. Without a type, pick one from a list. Pass a date to backfill. |

Meeting types: `planning`, `refinement`, `review`, `retro`, `1on1` (asks for the person), `adhoc` (asks
for a title). Each new meeting note starts with YAML frontmatter, uses its type's template and is
linked under `## Meetings` in that day's daily note. Accented titles are transliterated in filenames
(`Reunión con QA` → `2026-10-14 - reunion-con-qa.md`); the note keeps the original title.

Every subcommand has a `<Plug>` mapping. Example keymaps:

```lua
vim.keymap.set("n", "<leader>jd", "<Plug>(logpose-daily)", { desc = "Daily note" })
vim.keymap.set("n", "<leader>jm", "<Plug>(logpose-meeting)", { desc = "Meeting note" })
vim.keymap.set("n", "<leader>jc", "<Plug>(logpose-capture)", { desc = "Capture to INBOX" })
vim.keymap.set({ "n", "x" }, "<leader>jx", "<Plug>(logpose-done)", { desc = "Mark done" })
vim.keymap.set("n", "<leader>jf", "<Plug>(logpose-find)", { desc = "Find notes" })
vim.keymap.set("n", "<leader>jt", "<cmd>Logpose find tasks open<cr>", { desc = "Open tasks" })
vim.keymap.set("n", "<leader>j/", "<Plug>(logpose-grep)", { desc = "Grep journal" })
```

### Archiving

`INBOX.md` and `DONE.md` hold `## YYYY-MM-DD` sections. `:Logpose archive` moves every section
from before the current week into `journal-entries/week-<monday>.md` (from INBOX) and
`done-entries/done-week-<monday>.md` (from DONE), merging into week files that already exist.
Current-week sections, the title and any non-date sections (`## Someday`) stay put. If either
file has unsaved changes, nothing is written. Running it again is always safe.

To archive by sprint instead, give logpose the start date of any one sprint and its number. For
two-week sprints running Thursday to Wednesday:

```lua
period = {
  kind = "sprint",
  sprint = { anchor = "2026-10-01", length_days = 14, first_number = 42 },
},
```

Sprints are counted from the anchor in both directions, so 2026-10-15 → 2026-10-28 is `sprint-43`.
Archives go to `journal-entries/sprint-42.md` and `done-entries/done-sprint-42.md`, and `{sprint}`
works in templates. To keep weekly archives aligned with Thursday sprints, use
`period = { week_start = 4 }` instead.

### Projects

One journal can hold several unrelated projects. You keep a single daily note (and standup), while
meeting notes are filed per project:

- The active project is the git repo you're working in (`~/work/acme-api` → `acme-api`), a name
  you map in `projects.paths`, or one you pin with `:Logpose project <name>`. Inside the journal
  itself there is no project.
- With a project, `:Logpose meeting retro` writes `meetings/<project>/<date> - retro.md`, adds
  `project: <name>` to the frontmatter, and links it in the daily note as
  `- acme-api: [[meetings/acme-api/2026-10-14 - retro|Retro]]`. Recurring meetings are grouped per
  project.
- `require("logpose").project()` returns the active project, e.g. for your statusline.

### Searching

`:Logpose find` works with snacks.picker (LazyVim's default), fzf-lua or Telescope, whichever is
installed, and falls back to `vim.ui.select`. Logpose builds the results itself, so every picker
shows the same thing.

Scopes: `notes` (default), `daily`, `meetings`, `archives`, `tasks`, `tags`, `projects`.
Filters, all combined with AND (with completion):

| Filter | Matches |
|---|---|
| `project:acme` | items of project `acme`, or tagged `#acme` |
| `#perf` / `tag:perf` | items carrying the tag |
| `type:retro` | meetings of that type |
| `open` / `done` | tasks by state |
| `since:2026-10-01` / `until:2026-10-14` | by date |
| other words | must all appear in the text |

```vim
:Logpose find meetings project:acme
:Logpose find tasks open #perf
:Logpose find tags          " pick a tag, then everything tagged with it
:Logpose find projects      " pick a project, then its notes and tasks
```

Tags are inline `#words` (not headings, URL fragments or issue numbers like `#123`) plus
frontmatter `tags: [a, b]`, compared case-insensitively.

### Templates

Put `<name>.md` in your journal's templates directory (`dirs.templates`) to override a shipped
template (`daily`, `meeting`, `planning`, `refinement`, `review`, `retro`, `1on1`). Variables:
`{date}`, `{time}`, `{weekday}`, `{iso_week}`, `{title}`, `{type}`, `{type_label}`, `{series}`,
`{project}`, `{sprint}` (with a sprint anchor configured).
`{cursor}` marks where the cursor lands.

## Configuration

`setup()` is optional. Defaults:

```lua
require("logpose").setup({
  root = nil,                            -- journal path; overrides the one saved by :Logpose init
  root_markers = { ".logpose" },         -- used to find the root when `root` is nil
  dirs = {                               -- relative to the root
    daily = "daily",
    meetings = "meetings",
    inbox = "INBOX.md",
    done = "DONE.md",
    journal_entries = "journal-entries",
    done_entries = "done-entries",
    templates = "templates",
    reports = "reports",
  },
  affixes = { daily = "daily-", week = "week-", done_week = "done-week-", sprint = "", done_sprint = "done-" },
  link_style = "wiki",                   -- or "markdown"
  link_base = "",                        -- wiki-link targets are relative to this dir ("" = root)
  workdays = { 1, 2, 3, 4, 5 },          -- ISO weekdays, Monday = 1
  picker = "auto",                       -- "snacks" | "fzf_lua" | "telescope" | "select"
  meeting_filename = "{date} - {slug}",  -- may add {time} (HHMM) for several same-title meetings a day
  meeting_subdir = "{project}",          -- meetings/<project>/; "" keeps all meetings in one folder
  section_order = "auto",               -- order of ## YYYY-MM-DD sections: follow the file, or force
                                         -- "newest_first" / "oldest_first"
  archive = {
    journal_title = "# Journal: {period_label}", -- "week of 2026-10-05" / "sprint-42 (… – …)"
    done_title = "# Done: {period_label}",
  },
  period = {
    kind = "week",                       -- or "sprint"
    week_start = 1,                      -- ISO weekday weeks start on (4 = Thursday)
    sprint = { anchor = nil, length_days = 14, first_number = 1, name = "sprint-{n}" },
  },
  projects = {
    detect = true,                       -- the git repo you're in is the project
    paths = {},                          -- { ["~/work/acme-api"] = "acme" }; longest match wins
  },
  meeting_types = {
    -- title = fixed title (no prompt); prompt = ask, and {input} goes into title
    planning   = { label = "Sprint planning", template = "planning", title = "Sprint planning", order = 10 },
    refinement = { label = "Refinement", template = "refinement", title = "Refinement", order = 20 },
    review     = { label = "Sprint review", template = "review", title = "Sprint review", order = 30 },
    retro      = { label = "Retrospective", template = "retro", title = "Retro", order = 40 },
    ["1on1"]   = { label = "1:1", template = "1on1", prompt = "Person: ", title = "1:1 {input}", order = 50 },
    adhoc      = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
  },
})
```

The journal root is resolved in this order: `root` → a marker above the current buffer → a marker
above the current directory → the journal saved by `:Logpose init`.

An existing journal with a different layout just needs `dirs` (and `link_base` if wiki links
should be relative to a subdirectory):

```lua
opts = {
  root = "~/repos/my-journal",
  link_base = "journal",
  dirs = {
    daily = "journal/daily",
    meetings = "journal/meetings",
    inbox = "journal/INBOX.md",
    done = "journal/DONE.md",
    journal_entries = "journal/journal-entries",
    done_entries = "journal/done-entries",
    templates = "journal/templates",
    reports = "journal/reports",
  },
}
```

Add your own meeting types (e.g. `standup = { label = "Standup", title = "Standup" }`) or remove one
with `retro = false`.

Run `:checkhealth logpose` to see the resolved root and which paths exist.

## Development

```sh
make test                              # full suite (clones mini.nvim into deps/ on first run)
make test-file FILE=tests/test_date.lua
make lint                              # stylua --check
make format
```

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md) and
run with `TZ=America/New_York` so date math is exercised across DST changes. CI runs Neovim 0.10,
stable and nightly.

## License

Apache 2.0

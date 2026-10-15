# logpose.nvim

Daily notes, meeting notes and sprint archives for Scrum/Kanban developers, in Neovim.

> **Status: early development.** Onboarding, daily and meeting notes work; archiving lands next.
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
```

### Templates

Put `<name>.md` in your journal's templates directory (`dirs.templates`) to override a shipped
template (`daily`, `meeting`, `planning`, `refinement`, `review`, `retro`, `1on1`). Variables:
`{date}`, `{time}`, `{weekday}`, `{iso_week}`, `{title}`, `{type}`, `{type_label}`, `{series}`.
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
  affixes = { daily = "daily-", week = "week-", done_week = "done-week-" },
  link_style = "wiki",                   -- or "markdown"
  link_base = "",                        -- wiki-link targets are relative to this dir ("" = root)
  workdays = { 1, 2, 3, 4, 5 },          -- ISO weekdays, Monday = 1
  picker = "auto",                       -- "snacks" | "fzf_lua" | "telescope" | "select"
  meeting_filename = "{date} - {slug}",  -- may add {time} (HHMM) for several same-title meetings a day
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

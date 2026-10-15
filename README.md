# logpose.nvim

Daily notes, meeting notes and sprint archives for Scrum/Kanban developers, in Neovim.

> **Status: early development.** Daily and meeting notes work; archiving lands next.
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
  opts = {
    root = "~/path/to/your/journal", -- recommended: commands then work from any buffer
  },
}
```

For local development, use `dir = "~/Projects/logpose"` instead of the repo name.

## Usage

| Command | What it does |
|---|---|
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
  root = nil,                            -- absolute path to the journal repo
  root_markers = { ".llm-wiki-layout" }, -- used to find the root when `root` is nil
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
  affixes = { daily = "daily-", week = "week-", done_week = "done-week-" },
  link_style = "wiki",                   -- or "markdown"
  link_base = "journal",                 -- wiki-link targets are relative to this dir
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
above the current directory.

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

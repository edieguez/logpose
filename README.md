# logpose.nvim

**A sprint journal in Neovim.** Daily notes that prepare your standup, meeting notes that
remember last time's action items, and a Kanban board where every task is a markdown file.

![The logpose board: five columns of task cards with projects, tags, due dates and a blocked card](docs/images/board.png)

- **Plain markdown, no database.** Everything lives in a folder you choose. logpose reads the
  structure you already write: frontmatter, `## headings`, `#tags`, `@people` and `[[links]]`.
- **Built for Scrum.** It knows your sprints, so archives, reports and search filters work
  sprint by sprint.
- **Built for juggling projects.** It detects the project from the git repo you're in, and
  keeps meetings, tasks and the board apart per project.

Requires Neovim 0.10 or later.

## Contents

- **Start:** [Install](#install) · [Quick start](#quick-start) ·
  [How it fits a sprint](#how-it-fits-a-sprint)
- **Guide:** [Daily notes and standup](#daily-notes-and-standup) · [Meetings](#meetings) ·
  [Tasks and the board](#tasks-and-the-board) · [Today screen](#the-today-screen) ·
  [Projects](#projects) · [Search](#search) · [Action items](#action-items-and-people) ·
  [Links](#topic-notes-and-links) · [Sprints and reports](#sprints-archives-and-reports) ·
  [Extras](#extras)
- **Reference:** [Commands](#commands) · [Board keys](#board-keys) ·
  [Search filters](#search-filters) · [Keymaps](#keymaps) · [Configuration](#configuration) ·
  [Templates](#templates) · [Journal layout](#journal-layout) ·
  [Troubleshooting](#troubleshooting) · [Development](#development)

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim) (LazyVim included):

```lua
{
  "edieguez/logpose",
  cmd = "Logpose",
  ft = "markdown", -- enables `gx` on tickets and `[[` completion in journal notes
  opts = {
    keymaps = true, -- optional: a <leader>j… key set (see Keymaps)
  },
}
```

Optional, and used automatically when present:

| Plugin | What it adds |
|---|---|
| [snacks.nvim](https://github.com/folke/snacks.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua) or [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Search with live results and a preview. Without one, logpose uses `vim.ui.select` and the quickfix list. |
| [blink.cmp](https://github.com/Saghen/blink.cmp) or [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | Completion of `[[` note links ([setup](#topic-notes-and-links)). |
| A Nerd Font | Nicer board glyphs with `board = { icons = "nerd" }`. |

## Quick start

1. **Create a journal.** Run `:Logpose init` and accept `~/journal` (or type another folder).
   logpose creates `daily/`, `meetings/` and `tasks/` and remembers the folder, so every command
   works from any buffer. Pointing it at a folder that already has notes only adds a `.logpose`
   marker file.
2. **Tell it about your sprints** (skip if you work in weeks). Give it the start date and number
   of any one sprint:

   ```lua
   opts = {
     period = { kind = "sprint", sprint = { anchor = "2026-10-15", first_number = 43 } },
   }
   ```

3. **Start your day.** Run `:Logpose daily`, then `:Logpose board`.

Not sure what a command is called? Run `:Logpose` on its own for a menu of every command, with
what it does and the key you mapped to it. `:checkhealth logpose` shows which journal, project
and sprint logpose sees.

## How it fits a sprint

| When | Run | What you get |
|---|---|---|
| Start of the day | `:Logpose today` | Meetings, work in progress, blockers and what's due, on one screen. |
| | `:Logpose daily` | Today's note, with yesterday's finished and unfinished items already in place. |
| Before the standup | `:Logpose standup` | Yesterday / Today / Blockers, grouped by project, ready to read out. |
| Something comes up | `:Logpose capture Fix flaky test #ci` | A task in Backlog, without leaving what you're doing. |
| During the day | `:Logpose board` | Move cards with `H`/`L`, finish them with `x`, block them with `b`. |
| In a meeting | `:Logpose meeting retro` | A retro note with the last retro's open action items carried over. |
| After a meeting | `:Logpose promote` | Turns the action item under the cursor into a task file. |
| Sprint review | `:Logpose report sprint` | What got done, decisions, and what needs attention. |
| New sprint | `:Logpose archive` | Files away the last sprint's done tasks. |

---

## Daily notes and standup

**One note per workday, and a standup that writes itself.**

```vim
:Logpose daily          " today's note
:Logpose daily prev     " the previous workday's (also: next, or a date like 2026-10-14)
:Logpose standup        " Yesterday / Today / Blockers for the standup
```

When logpose creates today's note, it starts from your most recent note (Friday's on a
Monday):

- Items you checked off under `## Today` move to `## Yesterday`.
- Unfinished items move to the new `## Today`. In the old note they're marked `- [>]`, so each
  item lives in one place.
- Existing notes are never rewritten; only that marker changes.

`:Logpose standup` combines the daily note with the board:

```markdown
# Standup 2026-10-15

## Yesterday

### acme

- Review Ana's PR on the cache layer #acme

## Today

### acme

- [ ] Reproduce flaky checkout test #acme
- [ ] Speed up search indexing #acme

## Blockers

### acme

- Vendor SSO integration: waiting on Ana #acme
```

Tasks finished since the previous workday go under Yesterday, tasks in progress under Today,
and blocked tasks (with the reason) under Blockers. Items are grouped by their project tag.

> **Configure:** rename the sections with
> `standup = { sections = { yesterday = "Ayer", today = "Hoy", blockers = "Bloqueos" } }`.
> `include_done = true` also lists that day's DONE entries, if you use INBOX mode.

## Meetings

**Meeting notes from a template, linked from your daily note, with last time's open items
carried over.**

```vim
:Logpose meeting              " pick a type
:Logpose meeting retro        " or name it
:Logpose meeting 1on1         " asks who the 1:1 is with
:Logpose meeting adhoc 2026-10-14   " a date backfills a note
```

| Type | Asks for | Title |
|---|---|---|
| `planning`, `refinement`, `review`, `retro` | nothing | fixed (`Sprint planning`, …) |
| `1on1` | the person, with completion | `1:1 Ana` |
| `adhoc` | a title, with completion of past titles | what you type |

Each note gets frontmatter (type, date, title, attendees, project) and a link under
`## Meetings` in that day's daily note. Running the same command again on the same day opens
the existing note instead of making a second one.

**Series.** Meetings with the same type and title (or the same person, for 1:1s) form a series
within a project. A new note in a series starts with a `Previous: [[…]]` link and a
`## Carried over` section holding the previous note's open checkboxes. In the old note, those
are marked `- [>]`.

> **Configure:** add your own types in `meeting_types`
> (`standup = { label = "Standup", title = "Standup" }`), remove one (`retro = false`), or set
> `ask_attendees = true` on a type. Turn off carrying with `series = { carry_over = false }`.

## Tasks and the board

**Every task is a markdown file, so it has room for context. The board is how you move them.**

```vim
:Logpose capture Fix flaky test #ci due:2026-10-20   " new task in Backlog
:Logpose board                                       " the Kanban board
```

The board has five columns: **Backlog → TODO → In progress → Follow-up → Done**. Each card
shows:

- the title;
- `◆ project`, `#tags` and `◷ due date`, with overdue dates in red;
- `⊘ reason` and a red border when the task is blocked;
- how long the card has been in its column (`4d`). Cards untouched for a week fade, so
  forgotten work stands out.

In progress has a work-in-progress limit of 3: its header shows `(2/3)`, and the count turns red
above the limit.

### Working on the board

The essentials (the [full list](#board-keys) is in the reference, and `?` shows it on the
board):

| Key | Does |
|---|---|
| `h` `j` `k` `l` | Move between cards and columns. The mouse works too. |
| `H` `L` | Move the card to the previous / next column. `1`–`9` jump to column N. |
| `x` | Done. |
| `b` | Block (asks for the reason) or unblock. |
| `a` | Add a card to this column. |
| `K` | Peek: open the task in a floating window to read or edit it. |
| `<CR>` | Open the task file. |
| `u` / `<C-r>` | Undo / redo the last board change, exactly, log lines included. |

In a project's repo, the board shows that project's tasks. `p` shows all projects, `P` switches to
another project, and `m` moves the focused card to another project.

### What a task file looks like

You never edit `status` by hand: logpose moves it, records `started` and `done`, and appends a
line to `## Log` on every change.

```markdown
---
title: "Fix flaky checkout test"
status: in-progress
project: acme
tags: [ci]
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

### Other ways in and out

| From | Do | Result |
|---|---|---|
| Anywhere | `:Logpose capture text #tag due:DATE` | A Backlog task for the active project (`capture!` opens it). |
| A checkbox in a meeting or daily note | `:Logpose promote` | A TODO task with a `From:` link back, and the checkbox becomes a link to it. |
| A task file | `:Logpose done` | The task moves to Done. |
| A checkbox in any note | `:Logpose done` | The checkbox is checked off (works on a visual selection too). |
| An old `INBOX.md` | `:Logpose migrate` | Every open item becomes a task file (shows a preview first). |

> **Configure:** columns, WIP limits, colours and glyphs are all in [`board`](#configuration).
> Prefer a single checklist file? `tasks = { mode = "inbox" }` brings back the INBOX.md/DONE.md
> flow.

## The today screen

**Your day on one screen.**

![The today screen: meetings, work in progress, blocked tasks, what's due and overdue action items](docs/images/today.png)

`:Logpose today` lists today's meetings, cards in progress and blocked, tasks due within three
days, overdue action items, and what's left under Today in your daily note. Press `<CR>` on an
item to open it. `d` opens the daily note, `b` the board, `r` refreshes and `q` closes.

## Projects

**One journal, many projects, kept apart automatically.**

### Switching

`:Logpose project` (or `P` on the board) opens a switcher in your picker. The active project
comes first, then the ones you switched to recently, and each one previews what's going on in
it: work in progress, blocked tasks with their reasons, what's due and the last meeting.
Switching opens that project's board (if you're already on the board, it switches in place),
and takes effect everywhere else at once. `projects = { open_board = false }` switches without
leaving where you are.

```vim
:Logpose project          " the switcher
:Logpose project acme     " switch directly
:Logpose project none     " go back to automatic detection
```

When you haven't pinned a project, logpose works it out from where you are:

1. a match in `projects.paths` in your config;
2. a repo folder listed in a project's page (see below);
3. the git repo of the current file: `~/work/Acme API` becomes `acme-api`;
4. otherwise none. Inside the journal itself, there's no project.

With a project active:

- meeting notes go to `meetings/acme/` and their series stay within the project;
- captured tasks get `project: acme`;
- the board and the statusline show that project's tasks;
- daily-note links are prefixed: `- acme: [[…|Retro]]`.

### Managing projects

`:Logpose projects` shows every project with what needs attention: overdue, due-soon and blocked
tasks, work in progress, and how long ago anything happened. The most recently active projects
come first, and ones untouched for two weeks fade. `<Tab>` opens a project in place:

![The projects screen with Acme API expanded: its description, repo, work in progress, blocked task and last meeting](docs/images/projects.png)

| Key | Does |
|---|---|
| `<CR>` | Switch to the project. On a line inside an expanded project, open that task or note. |
| `<Tab>` | Show or hide what's going on in the project. |
| `b` | Open the project's board. |
| `n` | Open its project page. |
| `t` / `f` | Search its open tasks / its notes. |
| `a` | Add a project: its name, then its repo folder (suggested from where you came from). |
| `p` | Link another repo folder to the project. |
| `R` | Rename it everywhere: tasks, notes, tags, its meeting folder and page, and links. |
| `M` | Merge it into another project. |
| `D` / `U` | Archive it / restore it (`A` shows archived projects). |
| `c` | Go back to automatic detection. |

**The project page** (`projects/acme.md`) is where a project lives. Its frontmatter is what the
switcher and the manager show, and you can edit it by hand:

```markdown
---
title: "Acme API"
project: acme
description: Payments API for the Acme storefront
paths: [~/work/acme-api, ~/work/acme-web]
color: "#e0af68"
---
```

- `title` is the name you see. `project` is the short name used in commands and files.
- `paths` are the repo folders that belong to the project. Working in one of them makes it the
  active project, with no config needed.
- `color` (a hex colour or a highlight group) colours the project's cards on the board.
- The rest of the page is yours: overview, links, decisions, open questions.

**Moving a task to another project:** `m` on the board, or `:Logpose move [project]` in a task
file. The move is logged in the task, and `u` on the board undoes it.

**Merging** (`M`, or `:Logpose merge-project old new`) moves everything from one project into
another: tasks, notes, meetings (files and series) and links. The old project page stays,
archived and marked `merged_into`, so links to it keep working. Like a rename, it shows every
change before applying it.

**Archiving** hides a project you're done with, without losing anything. Its tasks and notes
stay where they are and remain searchable, but it leaves completion, the switcher and the
all-projects board. logpose records this as `archived: true` in the project page, and `U`
undoes it.

> **Configure:** `projects = { paths = { ["~/work/api"] = "acme" } }` also names a folder's
> project, from your config. `meeting_subdir = ""` keeps all meetings in one folder.

## Search

**Find anything in the journal, by text and by structure.**

```vim
:Logpose find                                  " all notes
:Logpose find tasks open #perf                 " open tasks tagged #perf
:Logpose find decisions project:acme sprint:-1 " last sprint's decisions for acme
:Logpose find people                           " everyone, then everything about one person
:Logpose grep                                  " plain live grep in the journal
```

The first word is the **scope**: `notes` (default), `daily`, `meetings`, `topics`, `archives`,
`tasks`, `decisions`, `blockers`, `tags`, `projects` or `people`. Everything after it is a
**filter**, and every filter must match. The most useful ones:

| Filter | Matches |
|---|---|
| `#perf` | items tagged `perf` |
| `project:acme` | items of a project |
| `@ana` | items involving Ana |
| `open` / `done` | tasks by state |
| `blocked` | blocked tasks |
| `sprint:current`, `sprint:-1`, `since:-7d` | a time range |
| any other word | must appear in the text |

All filters are in the [reference](#search-filters).

**Live search.** With snacks, fzf-lua or Telescope, the picker prompt holds the query: it starts
with what you typed on the command line, and results update as you edit it. Half-typed filters
such as `project:` are ignored until they're complete. Every result has a preview at its line.

**Decisions and blockers.** Every line under a `## Decisions`, `## Blockers`, `## Risks` or
`## Open questions` heading is searchable, tagged or not. That's what the `decisions` and
`blockers` scopes find.

> **Configure:** `search = { live = false }` gives fixed results that the picker fuzzy-filters
> instead. `retrieval.sections` sets which headings count.

## Action items and people

**Action items are checkboxes with an owner and a due date.**

```markdown
- [ ] Share load-test results @ana due:2026-10-21
```

```vim
:Logpose actions             " open action items from all meeting notes
:Logpose actions mine        " yours (set me = "@yourname"), plus unassigned ones
:Logpose actions overdue     " past their due date
:Logpose actions person:ana  " Ana's
```

They open in the quickfix list, soonest due first, with overdue items flagged. Filters work as
in `find`.

**People** come from meeting `attendees:`, 1:1s and `@mentions`. `:Logpose find people` lists
everyone with how much involves them; pick a person to see all of it.

## Topic notes and links

**Notes that aren't tied to a day, and links between everything.**

| Command | Does |
|---|---|
| `:Logpose note Queue design` | Creates or opens `notes/queue-design.md`, for how-tos, decision records and references. |
| `:Logpose project-page` | Creates or opens `projects/<project>.md`, the hub for a project. |
| `:Logpose backlinks` | Notes linking to the current one. |
| `:Logpose links` | Links going out of it, with missing targets flagged. |

Wiki links (`[[target|label]]`, or a short `[[name]]`) and relative markdown links both work.

**Link completion.** Typing `[[` in a journal note offers every note:

- **blink.cmp:** add `logpose = { name = "logpose", module = "logpose.completion.blink" }` to
  `sources.providers`, and `"logpose"` to your markdown sources.
- **nvim-cmp:** logpose registers the source itself; add `{ name = "logpose" }` to your markdown
  sources.

## Sprints, archives and reports

**logpose knows which sprint any date falls in.** Give it the start date and number of any one
sprint; the rest are counted in both directions:

```lua
period = {
  kind = "sprint",
  sprint = { anchor = "2026-10-15", length_days = 14, first_number = 43 },
},
```

This drives `sprint:` filters, the `{sprint}` template variable, the board's Done column (it
shows the current sprint), the statusline and the reports below. Without it, periods are
Monday-to-Sunday weeks.

**Reports.** `:Logpose report sprint` summarises the current sprint: tasks done, meetings,
decisions and open action items. A review section lists what needs attention: overdue action
items, blocked tasks, and tasks in progress for too long.

```vim
:Logpose report sprint -1               " the previous sprint
:Logpose report sprint -1 project:acme  " just one project
:Logpose report! sprint -1              " save it to reports/sprint-42.md
```

**Archive.** `:Logpose archive` moves done tasks from past sprints into
`tasks/archive/sprint-42/`, where reports and search still find them. It shows a preview and
asks first, and running it twice is harmless.

## Extras

### Statusline

`require("logpose").statusline()` returns something like
`acme · 2 in progress · 1 blocked · sprint-43 2/10`. It's cached, so it's cheap to call on every
redraw. For lualine:

```lua
sections = {
  lualine_x = { function() return require("logpose").statusline() end },
}
```

Hide parts with `statusline({ project = false, tasks = false, period = false })`, or change the
`separator`.

### Tickets

With `tickets = { url = "https://acme.atlassian.net/browse/{id}" }`, `gx` on `PROJ-123` in a
journal note opens the ticket. `:Logpose ticket` lists every line mentioning the ticket under
the cursor.

### Saved views

Name the searches you run often:

```lua
views = { acme = "tasks open project:acme", decisions = "decisions sprint:current" },
```

Then `:Logpose view acme`, or `:Logpose view` to pick one.

### Renaming tags and projects

`:Logpose rename-tag perf performance` and `:Logpose rename-project acme acme-web` rename
everywhere: tags, frontmatter, meeting folders, project pages and links. Both preview the
changes and ask first.

### Usage stats

On by default, and they never leave your machine: logpose counts which commands you use per
day, in a file only you can read. Turn them off with `telemetry = { enabled = false }`. It records command names only, never note
content or paths. `:Logpose stats` shows the counts and the commands you haven't tried. The
`:Logpose` menu also uses them to list your most-used commands first.

---

## Commands

Every command is `:Logpose <name>`, with `<Tab>` completion, and has a `<Plug>(logpose-<name>)`
mapping. A `!` can go on either word: `:Logpose archive!` is the same as `:Logpose! archive`.

### Daily work

| Command | Does |
|---|---|
| `today` | The day at a glance. |
| `daily [today\|prev\|next\|DATE]` | Open (and create) a daily note. `prev`/`next` step by workday. |
| `standup [DATE]` | Yesterday / Today / Blockers in a scratch buffer. |
| `meeting [TYPE] [DATE]` | New meeting note. |

### Tasks

| Command | Does |
|---|---|
| `board [FILTERS]` | The Kanban board. |
| `capture[!] [TEXT]` | New task in Backlog. `!` opens it. |
| `done` | In a task file: move it to Done. On checkboxes: check them off. |
| `promote` | Turn the checkbox under the cursor into a task file. |
| `move [PROJECT\|none]` | In a task file: move the task to another project. |
| `triage [FILTERS]` | Open the board on Backlog. |
| `migrate[!]` | Turn open INBOX.md items into task files. `!` skips the preview. |
| `actions [open\|mine\|overdue\|all] [FILTERS]` | Meeting action items in the quickfix list. |

### Finding things

| Command | Does |
|---|---|
| `find [SCOPE] [FILTERS]` | Search the journal. |
| `grep [TEXT]` | Live grep in the journal. |
| `view [NAME]` | Run a saved search. |
| `ticket [ID]` | Every line mentioning a ticket. |
| `backlinks` / `links` | Links into / out of the current note. |

### Notes and projects

| Command | Does |
|---|---|
| `note [TITLE]` | Create or open a topic note. |
| `project [NAME\|none]` | Switch project (a picker without a name), or go back to detection. |
| `projects` | Manage projects: what needs attention, add, rename, merge, archive. |
| `project-page [NAME]` | Create or open a project page. |

### Sprints and maintenance

| Command | Does |
|---|---|
| `report[!] [week\|sprint] [OFFSET] [FILTERS]` | Week or sprint summary. `!` saves it. |
| `archive[!]` | File away done work from past periods. `!` skips the preview. |
| `rename-tag[!] OLD NEW` | Rename a tag everywhere. |
| `rename-project[!] OLD NEW` | Rename a project everywhere. |
| `merge-project[!] OLD NEW` | Merge one project into another. |
| `init [DIR]` | Choose or create the journal folder. |
| `stats[!] [DAYS]` | Usage stats. `!` resets them. |

## Board keys

| Key | Action | Key | Action |
|---|---|---|---|
| `h` `l` | previous / next column | `j` `k` | previous / next card |
| `H` `L` (`<` `>`) | move the card left / right | `1`–`9` | move it to column N |
| `x` | done | `b` | block (asks why) / unblock |
| `<C-j>` `<C-k>` | move the card down / up | `a` | add a card to this column |
| `K` | peek in a floating window | `D` | delete the card (asks first) |
| `z` | fold / unfold the column | `gg` `G` | first / last card |
| `u` | undo | `<C-r>` | redo |
| `c` | compact one-line cards | `s` | one row per project |
| `<CR>` | open the task file | `/` | filter (same filters as `find`) |
| `p` | this project / all projects | `P` | switch project |
| `m` | move the card to another project | `r` | refresh |
| `q` | close | `?` | help |

## Search filters

| Filter | Matches |
|---|---|
| `project:acme` | items of the project, or tagged `#acme` |
| `#perf`, `tag:perf` | tagged items |
| `@ana`, `person:ana` | items involving the person: attendee, 1:1, or @mention |
| `type:retro` | meetings of that type |
| `open`, `done` | tasks by state (checkboxes and task files) |
| `status:in-progress` | task files in that board column |
| `blocked` | blocked task files |
| `since:DATE`, `until:DATE` | `2026-10-14`, `today`, `yesterday`, `tomorrow`, `-7d`, `+2w` |
| `week:current`, `sprint:-1`, `sprint:42` | a whole week or sprint |
| `section:decisions` | lines under a matching `##` heading |
| any other word | must appear in the text |

Tags are inline `#words` (not headings, URL fragments or numbers like `#123`) and frontmatter
`tags: [a, b]`, compared without case.

## Keymaps

logpose sets no keys unless you ask. `keymaps = true` installs this set under `<leader>j`
(choose another prefix with `keymaps = { prefix = "<leader>n" }`). It's labelled for which-key,
and it never replaces a key you've mapped yourself.

| Key | Action | Key | Action |
|---|---|---|---|
| `<leader>jj` | command menu | `<leader>jd` | daily note |
| `<leader>jy` | today | `<leader>js` | standup |
| `<leader>jk` | board | `<leader>jm` | meeting note |
| `<leader>jw` | switch project | `<leader>jP` | manage projects |
| `<leader>jc` | capture a task | `<leader>jx` | mark done (normal and visual) |
| `<leader>jp` | promote to task file | `<leader>jn` | topic note |
| `<leader>jf` | find notes | `<leader>jt` | open tasks |
| `<leader>ja` | action items | `<leader>jb` | backlinks |
| `<leader>jr` | report | `<leader>j/` | grep the journal |

To choose your own keys, map the `<Plug>` mappings instead:

```lua
vim.keymap.set("n", "<leader>jd", "<Plug>(logpose-daily)", { desc = "Daily note" })
vim.keymap.set("n", "<leader>jt", "<cmd>Logpose find tasks open<cr>", { desc = "Open tasks" })
```

## Configuration

`setup()` is optional: every command works with the defaults. These are the options you're most
likely to change:

```lua
require("logpose").setup({
  root = nil,              -- journal path; by default the one chosen with :Logpose init
  me = nil,                -- your handle in action items, e.g. "@ana"
  keymaps = false,         -- true for the <leader>j… set
  workdays = { 1, 2, 3, 4, 5 },   -- ISO weekdays, Monday = 1
  period = {
    kind = "week",         -- or "sprint"
    week_start = 1,        -- weeks start on Monday
    sprint = { anchor = nil, length_days = 14, first_number = 1, name = "sprint-{n}" },
  },
  projects = {
    detect = true,         -- the git repo you're in is the project
    paths = {},            -- { ["~/work/acme-api"] = "acme" }; the longest match wins
    open_board = true,     -- switching project opens its board
  },
  link_style = "wiki",     -- or "markdown"
  picker = "auto",         -- "snacks" | "fzf_lua" | "telescope" | "select"
})
```

Unknown options produce a warning and invalid values an error. Lists replace the default rather
than merging with it.

<details>
<summary><b>Board</b></summary>

```lua
board = {
  columns = {
    { key = "backlog", label = "Backlog" },
    { key = "todo", label = "TODO" },
    { key = "in-progress", label = "In progress", limit = 3 },  -- limit: WIP limit
    { key = "follow-up", label = "Follow-up" },
    { key = "done", label = "Done" },
    -- each column may also set hl = "<highlight group>" for its colour
  },
  start = "in-progress",   -- reaching this column records `started:`
  done = "done",           -- reaching this column records `done:`
  done_window = "period",  -- Done shows the current week or sprint, or a number of days
  min_column_width = 24,   -- below this width, columns stack vertically
  stale_days = 7,          -- cards untouched this long fade
  collapsed = {},          -- column keys folded when the board opens, e.g. { "done" }
  icons = "unicode",       -- or "nerd" (Nerd Font) or "ascii"
  compact = false,         -- start with one-line cards (c toggles)
  lanes = false,           -- start with one row per project (s toggles)
  open = "window",         -- or "tab": open the board in its own tab page
},
tasks = {
  mode = "files",          -- or "inbox" for the INBOX.md/DONE.md checkbox flow
  capture_status = "backlog",   -- column for :Logpose capture
  promote_status = "todo",      -- column for :Logpose promote
},
```

Colours come from highlight groups linked to your colour scheme's diagnostic colours. Override
`LogposeBoardColumn1` to `LogposeBoardColumn5`, `LogposeBoardFocus`, `LogposeBoardBlocked`,
`LogposeBoardOverdue`, `LogposeBoardProject`, `LogposeBoardTag`, `LogposeBoardTitle` or
`LogposeBoardHint` to change them.

</details>

<details>
<summary><b>Notes, meetings and standup</b></summary>

```lua
meeting_filename = "{date} - {slug}",  -- add {time} (HHMM) to allow several per day
meeting_subdir = "{project}",          -- "" keeps all meetings in one folder
meeting_types = {
  planning   = { label = "Sprint planning", template = "planning", title = "Sprint planning", order = 10 },
  refinement = { label = "Refinement", template = "refinement", title = "Refinement", order = 20 },
  review     = { label = "Sprint review", template = "review", title = "Sprint review", order = 30 },
  retro      = { label = "Retrospective", template = "retro", title = "Retro", order = 40 },
  ["1on1"]   = { label = "1:1", template = "1on1", prompt = "Person: ", title = "1:1 {input}", person = true, order = 50 },
  adhoc      = { label = "Ad-hoc", template = "meeting", prompt = "Meeting title: ", order = 60 },
  -- a type may also set ask_attendees = true; set a type to false to remove it
},
series = { carry_over = true, mark_carried = true },
standup = {
  sections = { yesterday = "Yesterday", today = "Today", blockers = "Blockers" },
  carry_forward = true, mark_carried = true, include_done = false, group_by_project = true,
},
timestamps = { created = true, modified = true },  -- created:/modified: in frontmatter
section_order = "auto",                -- "newest_first" | "oldest_first"
```

</details>

<details>
<summary><b>Search, action items and reports</b></summary>

```lua
search = { live = true },              -- the picker prompt re-runs the query as you type
retrieval = { sections = { "decisions", "blockers", "risks", "open questions" } },
views = {},                            -- saved searches: name = "find arguments"
actions = {
  include_daily = false,               -- also collect checkboxes from daily notes
  unassigned_mine = true,              -- items without an owner count as yours
  output = "quickfix",                 -- or "picker"
},
review = { stale_days = 14 },          -- "in progress for too long" in reports
tickets = { pattern = "%u[%u%d]+%-%d+", url = nil },
telemetry = { enabled = true, retention_days = 180 },  -- local only; false to turn off
```

</details>

<details>
<summary><b>Folders and file names</b> (for an existing journal with its own layout)</summary>

```lua
root_markers = { ".logpose" },
dirs = {                               -- relative to the journal root
  daily = "daily", meetings = "meetings", notes = "notes", projects = "projects", tasks = "tasks",
  inbox = "INBOX.md", done = "DONE.md",
  journal_entries = "journal-entries", done_entries = "done-entries",
  templates = "templates", reports = "reports",
},
affixes = { daily = "daily-", week = "week-", done_week = "done-week-", sprint = "", done_sprint = "done-" },
link_base = "",                        -- wiki-link targets are relative to this folder
archive = { journal_title = "# Journal: {period_label}", done_title = "# Done: {period_label}" },
```

For example, a journal kept in a subfolder of a repo:

```lua
opts = {
  root = "~/repos/notes",
  link_base = "journal",
  dirs = { daily = "journal/daily", meetings = "journal/meetings", templates = "journal/templates" },
}
```

logpose finds the journal in this order: `root`, then a `.logpose` marker above the current
file, then one above the current directory, then the journal chosen with `:Logpose init`.

</details>

## Templates

logpose ships templates for `daily`, `meeting`, `planning`, `refinement`, `review`, `retro`,
`1on1`, `note`, `project` and `task`. To change one, put a file with the same name in your
journal's `templates/` folder.

| Variable | Becomes |
|---|---|
| `{date}`, `{time}`, `{weekday}` | `2026-10-15`, `09:05`, `Thursday` |
| `{iso_week}`, `{sprint}` | `2026-W42`, `sprint-43` |
| `{title}`, `{type}`, `{type_label}` | the note's title and meeting type |
| `{project}`, `{series}`, `{attendees}` | from the active project and meeting |
| `{cursor}` | where the cursor lands (removed from the note) |

Unknown variables are left as they are.

**Timestamps.** New notes get `created:` and `modified:` in their frontmatter, e.g.
`2026-10-15T18:57`. `modified:` updates whenever logpose changes a note or you save one. Older
notes without the key are left alone; add it to opt one in.

**markdownlint.** Every note logpose creates passes markdownlint's default rules. Notes with a
`title:` in the frontmatter start at `##`, because markdownlint counts that title as the
document's heading (rule MD025). logpose keeps the blank lines markdownlint wants around the
headings, lists and code it inserts, and never rewraps your own text.

## Journal layout

```text
~/journal/
├── .logpose                         marks the journal root
├── daily/daily-2026-10-15.md
├── meetings/
│   ├── acme-api/2026-10-14 - retro.md
│   └── 2026-10-13 - 1-1-ana.md      meetings outside any project
├── tasks/
│   ├── fix-flaky-test.md            one file per task
│   └── archive/sprint-42/           done tasks from past sprints
├── notes/queue-design.md
├── projects/acme-api.md
├── reports/sprint-42.md
└── templates/                       your template overrides
```

Checkboxes in notes: `- [ ]` open, `- [x]` done, `- [>]` carried to a newer note.

## Troubleshooting

- **Start with `:checkhealth logpose`.** It shows the journal root and how it was found, the
  active project, the current week or sprint, which folders exist, the picker in use, and
  whether usage stats are on.
- **"Wrong project" or "no tasks on the board":** check the active project in the health report.
  `:Logpose project none` resets a pinned project, and `p` on the board shows all projects.
- **A file wasn't changed:** logpose never overwrites a file with unsaved changes. It edits the
  open buffer instead, or refuses and tells you.
- **Search has no preview:** install one of the [optional pickers](#install).

## Development

```sh
make test                               # full suite (fetches mini.nvim into deps/ the first time)
make test-file FILE=tests/test_date.lua
make lint                               # stylua --check, and no accidental globals
make lint-md                            # markdownlint on templates and generated notes
make format
```

To check speed on a big journal, generate one and time the everyday operations:

```sh
python3 scripts/bench/gen_journal.py /tmp/journal --years 5
nvim --headless -u NONE -i NONE --cmd "set rtp^=$PWD" -l scripts/bench/bench.lua /tmp/journal
```

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md).
Each case runs in a fresh child Neovim, with `TZ=America/New_York` so date math crosses real
daylight-saving changes. The suite takes seconds. CI runs Neovim 0.10, stable and nightly. `scripts/screenshots.sh`
regenerates the images in this README from a demo journal.

The design and roadmap are in [`docs/SPEC.md`](docs/SPEC.md). Releases are tagged
`MAJOR.MINOR.PATCH`; `git tag -n` lists what each one added.

## License

Apache 2.0

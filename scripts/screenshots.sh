#!/usr/bin/env bash
# Regenerates docs/images/*.png from a demo journal: renders the board and today screen in
# headless Neovim with tokyonight, exports them with :TOhtml and screenshots them with Playwright.
# Needs Neovim 0.11+, git, curl, and Python with playwright (`pip install playwright`, then
# `playwright install chromium`).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
# The temp dir's real path: on macOS it sits under /var, a symlink to /private/var, and Neovim names
# buffers by the resolved path, which then doesn't look like it's inside the journal.
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work"' EXIT
# Neovim's data and state go in the temp dir too, so logpose's saved state (the active project,
# recent projects) and usage stats from the demo journal never land in yours.
export XDG_DATA_HOME="$work/data" XDG_STATE_HOME="$work/state"
git clone -q --depth 1 https://github.com/folke/tokyonight.nvim "$work/tokyonight"
# DejaVu Sans Mono, which shot.py embeds in the pages it screenshots
curl -fsSL https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2 |
  tar -xjf - -C "$work"
nv() {
  nvim --headless -u NONE -i NONE --cmd "set rtp^=$repo" --cmd "set rtp^=$work/tokyonight" \
    --cmd "lua _G.ROOT='$work/journal'; _G.OUT='$work/$1'; _G.CMD='$2'; _G.COLS='$3'; _G.KEYS='${5:-}'; _G.TYPE='${6:-}'" \
    -c "lua local ok, e = pcall(dofile, '$4'); if not ok then io.stderr:write(e .. '\n') end; if not _G.ASYNC then vim.cmd('qa!') end"
}
nv seed "" 0 "$repo/scripts/screenshots/seed.lua"
nv board "Logpose board" 132 "$repo/scripts/screenshots/render.lua"
nv today "Logpose today" 90 "$repo/scripts/screenshots/render.lua"
nv notes "Logpose notes" 120 "$repo/scripts/screenshots/render.lua"
nv meetings "Logpose meetings" 132 "$repo/scripts/screenshots/render.lua"
nv people "Logpose people" 132 "$repo/scripts/screenshots/render.lua"
nv projects "Logpose projects" 112 "$repo/scripts/screenshots/render.lua" "/Acme<CR><Tab>"
nv edit "edit tasks/flaky-test.md | Logpose edit" 90 "$repo/scripts/screenshots/render.lua" "" "jSIn progress<Esc>jSthes<Tab><CR><Esc>2jSfri<Esc>"
python3 "$repo/scripts/screenshots/shot.py" "$work" "$repo/docs/images"

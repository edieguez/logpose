#!/usr/bin/env bash
# Regenerates docs/images/*.png from a demo journal: renders the board and today screen in
# headless Neovim with tokyonight, exports them with :TOhtml and screenshots them with Playwright.
# Needs Neovim 0.11+, git, and Python with playwright (`pip install playwright`).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 https://github.com/folke/tokyonight.nvim "$work/tokyonight"
nv() {
  nvim --headless -u NONE -i NONE --cmd "set rtp^=$repo" --cmd "set rtp^=$work/tokyonight" \
    --cmd "lua _G.ROOT='$work/journal'; _G.OUT='$work/$1'; _G.CMD='$2'; _G.COLS='$3'; _G.KEYS='${5:-}'" \
    -c "lua local ok, e = pcall(dofile, '$4'); if not ok then io.stderr:write(e .. '\n') end; vim.cmd('qa!')"
}
nv seed "" 0 "$repo/scripts/screenshots/seed.lua"
nv board "Logpose board" 132 "$repo/scripts/screenshots/render.lua"
nv today "Logpose today" 90 "$repo/scripts/screenshots/render.lua"
nv projects "Logpose projects" 112 "$repo/scripts/screenshots/render.lua" "/Acme<CR><Tab>"
python3 "$repo/scripts/screenshots/shot.py" "$work" "$repo/docs/images"

#!/bin/sh
# Lint the templates and every note logpose generates with markdownlint's default rules.
# Needs markdownlint-cli2 (npm install -g markdownlint-cli2).
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# Its own data and state folders: your pinned project doesn't shape the notes, and the run
# doesn't count in your usage stats.
XDG_DATA_HOME="$dir/data" XDG_STATE_HOME="$dir/state" TZ=America/New_York \
  ${NVIM:-nvim} --headless --clean -u scripts/lint-output.lua -- "$dir/journal"
markdownlint-cli2 "templates/*.md"
cd "$dir/journal" && markdownlint-cli2 "**/*.md"

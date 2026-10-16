#!/bin/sh
# Lint the templates and every note logpose generates with markdownlint's default rules.
# Needs markdownlint-cli2 (npm install -g markdownlint-cli2).
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
TZ=America/New_York ${NVIM:-nvim} --headless --clean -u scripts/lint-output.lua -- "$dir/journal"
markdownlint-cli2 "templates/*.md"
cd "$dir/journal" && markdownlint-cli2 "**/*.md"

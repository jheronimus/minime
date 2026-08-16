#!/bin/sh
# Check git diffs for whitespace errors and merge-conflict markers.
# Covers both staged content (pre-commit) and the working tree.
# Max SLOC: 100

set -eu

git diff --check
git diff --cached --check

#!/bin/sh
# Validate GitHub Actions workflow files with actionlint (via mise).
# Max SLOC: 100

set -eu

exec mise exec -- actionlint

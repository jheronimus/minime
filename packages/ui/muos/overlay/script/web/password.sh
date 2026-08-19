#!/bin/sh
set -eu

# Trigger network connection with saved credentials
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -x "${SCRIPT_DIR}/init/async/S02network.sh" ]; then
	exec "${SCRIPT_DIR}/init/async/S02network.sh" connect
fi

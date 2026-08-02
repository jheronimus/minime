#!/usr/bin/env sh
set -eu

echo "Checking Allium Rust code (cargo fmt & cargo clippy)..."
if [ ! -d "minime/ui/allium" ]; then
    echo "ERROR: minime/ui/allium directory not found" >&2
    exit 1
fi

(
    cd minime/ui/allium
    cargo fmt --all -- --check
    cargo clippy --all-targets -- -D warnings
)
echo "Allium Rust validation passed cleanly."

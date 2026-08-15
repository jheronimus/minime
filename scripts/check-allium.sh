#!/usr/bin/env sh
set -eu

echo "Checking Allium Rust code (cargo fmt & cargo clippy)..."
if [ ! -d "minime/ui/allium" ]; then
    echo "ERROR: minime/ui/allium directory not found" >&2
    exit 1
fi

cargo fmt --manifest-path minime/ui/allium/Cargo.toml --all -- --check
RUSTFLAGS="-A clippy::double_must_use" cargo clippy --manifest-path minime/ui/allium/Cargo.toml --all-targets -- -D warnings
echo "Allium Rust validation passed cleanly."

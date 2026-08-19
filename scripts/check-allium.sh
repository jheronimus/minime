#!/usr/bin/env sh
set -eu

echo "Checking Allium Rust code (cargo fmt & cargo clippy)..."
if [ ! -d "packages/ui/allium" ]; then
    echo "ERROR: packages/ui/allium directory not found" >&2
    exit 1
fi

cargo fmt --manifest-path packages/ui/allium/Cargo.toml --all -- --check
RUSTFLAGS="-A clippy::double_must_use" cargo clippy --manifest-path packages/ui/allium/Cargo.toml --all-targets -- -D warnings
echo "Allium Rust validation passed cleanly."

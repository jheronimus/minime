#!/bin/bash
set -euo pipefail

UI="${1:-}"
LIBC="${2:-}"

if [ -z "$UI" ] || [ -z "$LIBC" ]; then
	echo "Usage: $0 <ui> <libc>" >&2
	exit 1
fi

ROOT_DIR="$(pwd)"
mkdir -p "$ROOT_DIR/minime/ui/out"
OWNER="${GITHUB_REPOSITORY_OWNER:-jheronimus}"

if [ "$UI" = "minui" ]; then
	echo "Building MinUI binaries for ${LIBC}..."
	cd "$ROOT_DIR/minime/ui/minui"
	rm -rf releases build
	make setup

	if [ "$LIBC" = "musl" ]; then
		docker run --rm -u root \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			-v "$GITHUB_WORKSPACE:/workspace" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/minime/ui/minui/workspace && make CROSS_COMPILE=\"ccache \" PREFIX=/usr CC=\"ccache gcc\" CXX=\"ccache g++\" && cd .. && make CROSS_COMPILE=\"ccache \" PREFIX=/usr system cores PLATFORM=minime"
	else
		docker run --rm -u root \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			-v "$GITHUB_WORKSPACE:/workspace" \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/minime/ui/minui/workspace && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr CC=\"ccache aarch64-linux-gnu-gcc\" CXX=\"ccache aarch64-linux-gnu-g++\" && cd .. && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr system cores PLATFORM=minime"
	fi

	# Native PICO-8 (P8-NATIVE.pak + Splore.pak) launches the official glibc
	# pico8_64 binary (Raspberry Pi build). It cannot run on musl (Alpine),
	# so only ship it on glibc (Buildroot) builds.
	if [ "$LIBC" = "musl" ]; then
		echo "Skipping P8-NATIVE.pak + Splore.pak (require glibc) for ${LIBC} build..."
		rm -rf "$ROOT_DIR/minime/ui/minui/build/EXTRAS/Emus/minime/P8-NATIVE.pak"
		rm -rf "$ROOT_DIR/minime/ui/minui/build/EXTRAS/Tools/minime/Splore.pak"
	fi

	make package
	STAGE_DIR=$(mktemp -d)
	for zipfile in releases/*.zip; do
		[ -f "$zipfile" ] || continue
		unzip -q -o "$zipfile" -d "$STAGE_DIR"
	done
	cd "$ROOT_DIR"
	tar -cJf "$ROOT_DIR/minime/ui/out/minui-${LIBC}-aarch64.tar.xz" -C "$STAGE_DIR" .

elif [ "$UI" = "allium" ]; then
	echo "Building Allium binaries for ${LIBC}..."
	if [ "$LIBC" = "musl" ]; then
		TARGET="aarch64-unknown-linux-musl"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "cd /workspace/minime/ui/allium && cargo build --release --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/allium/target"

		mkdir -p minime/ui/allium/target/${TARGET}
		ln -sf ../release minime/ui/allium/target/${TARGET}/release
	else
		TARGET="aarch64-unknown-linux-gnu"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			-e CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "cd /workspace/minime/ui/allium && cargo build --release --target ${TARGET} --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/allium/target"
	fi

	BUILD="minime/ui/allium/target/${TARGET}/release"
	STATIC="minime/ui/allium/static"
	STAGE_DIR=$(mktemp -d)

	mkdir -p "$STAGE_DIR/.ui/bin"
	mkdir -p "$STAGE_DIR/.ui/config"
	mkdir -p "$STAGE_DIR/.ui/state"
	mkdir -p "$STAGE_DIR/.ui/themes"
	mkdir -p "$STAGE_DIR/.ui/fonts"
	mkdir -p "$STAGE_DIR/.tmp_update/bin"
	mkdir -p "$STAGE_DIR/apps"
	mkdir -p "$STAGE_DIR/RetroArch"
	mkdir -p "$STAGE_DIR/Roms"
	mkdir -p "$STAGE_DIR/Saves"
	mkdir -p "$STAGE_DIR/BIOS"

	cp $BUILD/alliumd "$STAGE_DIR/.ui/bin/"
	cp $BUILD/allium-launcher "$STAGE_DIR/.ui/bin/"
	cp $BUILD/allium-menu "$STAGE_DIR/.ui/bin/"
	cp $BUILD/screenshot "$STAGE_DIR/.tmp_update/bin/"
	cp $BUILD/say "$STAGE_DIR/.tmp_update/bin/"
	cp $BUILD/show "$STAGE_DIR/.tmp_update/bin/"

	cp $BUILD/activity-tracker "$STAGE_DIR/apps/Activity Tracker.pak/" || true
	cp $BUILD/screenshot-viewer "$STAGE_DIR/apps/Screenshot Viewer.pak/" || true

	cp -r "$STATIC/Apps/Activity Tracker.pak/." "$STAGE_DIR/apps/Activity Tracker.pak/" || true
	cp -r "$STATIC/Apps/Screenshot Viewer.pak/." "$STAGE_DIR/apps/Screenshot Viewer.pak/" || true
	cp -r "$STATIC/Apps/"*.pak "$STAGE_DIR/apps/" 2>/dev/null || true

	cp -r "$STATIC/RetroArch/." "$STAGE_DIR/RetroArch/" || true
	[ -d "$STATIC/.minime" ] && cp -r "$STATIC/.minime" "$STAGE_DIR/" || true

	OUT_TAR="$ROOT_DIR/minime/ui/out/allium-${LIBC}-aarch64.tar.xz"
	tar -cJf "$OUT_TAR" -C "$STAGE_DIR" .
	echo "Created $OUT_TAR"
else
	echo "Unknown UI: $UI" >&2
	exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
	chown -R "$USER:$USER" "$ROOT_DIR/minime/ui/out" 2>/dev/null || true
else
	sudo chown -R "$USER:$USER" "$ROOT_DIR/minime/ui/out" 2>/dev/null || true
fi

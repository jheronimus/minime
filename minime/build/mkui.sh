#!/bin/sh
set -eu

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
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/minime/ui/minui/workspace && make CROSS_COMPILE=\"ccache \" PREFIX=/usr CC=\"ccache gcc\" CXX=\"ccache g++\" && cd .. && make CROSS_COMPILE=\"ccache \" PREFIX=/usr system PLATFORM=minime"
	else
		docker run --rm -u root \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			-v "$GITHUB_WORKSPACE:/workspace" \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/minime/ui/minui/workspace && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr CC=\"ccache aarch64-linux-gnu-gcc\" CXX=\"ccache aarch64-linux-gnu-g++\" && cd .. && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr system PLATFORM=minime"
	fi

	# Inject the shared cores (built once by build-cores) into the paks. The
	# submodule `cores:` rule copies them from CORES_DIR into SYSTEM/minime/cores.
	make -C "$ROOT_DIR/minime/ui/minui" cores PLATFORM=minime \
		CORES_DIR="$ROOT_DIR/minime/build/cores/out"

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
	tar -cf "$ROOT_DIR/minime/ui/out/minui-${LIBC}-aarch64.tar" -C "$STAGE_DIR" .
	zstd -q -9 -f "$ROOT_DIR/minime/ui/out/minui-${LIBC}-aarch64.tar"
	rm -f "$ROOT_DIR/minime/ui/out/minui-${LIBC}-aarch64.tar"

elif [ "$UI" = "allium" ]; then
	echo "Building Allium binaries for ${LIBC}..."
	if [ "$LIBC" = "musl" ]; then
		TARGET="aarch64-unknown-linux-musl"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "cd /workspace/minime/ui/allium && cargo build --release --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            make retroarch-aarch64 CC=\"ccache gcc\" CXX=\"ccache g++\"; \
            make tools-aarch64; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/allium/target /workspace/minime/ui/allium/dist"

		mkdir -p minime/ui/allium/target/${TARGET}
		ln -sf ../release minime/ui/allium/target/${TARGET}/release
	else
		TARGET="aarch64-unknown-linux-gnu"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			-e CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "cd /workspace/minime/ui/allium && cargo build --release --target ${TARGET} --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            make retroarch-aarch64 HOST=aarch64-linux-gnu CC=\"ccache aarch64-linux-gnu-gcc\" CXX=\"ccache aarch64-linux-gnu-g++\"; \
            make tools-aarch64 AARCH64_TARGET=aarch64-unknown-linux-gnu; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/allium/target /workspace/minime/ui/allium/dist"
	fi

	BUILD="minime/ui/allium/target/${TARGET}/release"
	STATIC="minime/ui/allium/static"
	STAGE_DIR=$(mktemp -d)

	mkdir -p "$STAGE_DIR/.ui/bin"
	mkdir -p "$STAGE_DIR/.ui/config"
	mkdir -p "$STAGE_DIR/.ui/state"
	mkdir -p "$STAGE_DIR/.ui/themes"
	mkdir -p "$STAGE_DIR/.ui/fonts"
	mkdir -p "$STAGE_DIR/apps"
	mkdir -p "$STAGE_DIR/RetroArch"
	mkdir -p "$STAGE_DIR/Roms"
	mkdir -p "$STAGE_DIR/Saves/CurrentProfile"
	mkdir -p "$STAGE_DIR/BIOS"

	cp $BUILD/alliumd "$STAGE_DIR/.ui/bin/"
	cp $BUILD/allium-launcher "$STAGE_DIR/.ui/bin/"
	cp $BUILD/allium-menu "$STAGE_DIR/.ui/bin/"
	cp $BUILD/screenshot "$STAGE_DIR/.ui/bin/"
	cp $BUILD/say "$STAGE_DIR/.ui/bin/"
	cp $BUILD/show "$STAGE_DIR/.ui/bin/"

	cp $BUILD/activity-tracker "$STAGE_DIR/apps/Activity Tracker.pak/" || true
	cp $BUILD/screenshot-viewer "$STAGE_DIR/apps/Screenshot Viewer.pak/" || true

	cp -r "$STATIC/Apps/Activity Tracker.pak/." "$STAGE_DIR/apps/Activity Tracker.pak/" || true
	cp -r "$STATIC/Apps/Screenshot Viewer.pak/." "$STAGE_DIR/apps/Screenshot Viewer.pak/" || true
	cp -r "$STATIC/Apps/"*.pak "$STAGE_DIR/apps/" 2>/dev/null || true

	cp -r "$STATIC/RetroArch/." "$STAGE_DIR/RetroArch/" || true
	# Inject the aarch64 RetroArch built by the retroarch-aarch64 target
	# (third-party/RetroArch-patch assembled source + the UDP-command patches
	# Allium's menu depends on).  The upstream static/RetroArch has no binary.
	if [ -f "$ROOT_DIR/minime/ui/allium/dist/RetroArch/retroarch" ]; then
		cp "$ROOT_DIR/minime/ui/allium/dist/RetroArch/retroarch" "$STAGE_DIR/RetroArch/retroarch"
	else
		echo "WARNING: retroarch binary not found — skipping injection" >&2
	fi
	# Inject the shared Minime cores (built once by build-cores) into RetroArch.
	# Allium's retroarch launch.sh loads `-L RetroArch/.retroarch/cores/<name>_libretro.so`,
	# so the flat artifact goes straight in, overwriting the committed stock cores.
	if [ -d "$ROOT_DIR/minime/build/cores/out" ]; then
		mkdir -p "$STAGE_DIR/RetroArch/.retroarch/cores"
		cp "$ROOT_DIR/minime/build/cores/out/"*.so "$STAGE_DIR/RetroArch/.retroarch/cores/" || true
	else
		echo "WARNING: cores artifact not found — skipping core injection" >&2
	fi
	# Stage the .allium runtime tree (config/cores/locales/fonts/scripts/
	# migrations) plus the bundled aarch64 tools (dufs/collie/syncthing)
	# built by the tools-aarch64 target into .allium/bin.
	cp -r "$STATIC/.allium/." "$STAGE_DIR/.allium/" 2>/dev/null || true
	mkdir -p "$STAGE_DIR/.allium/bin"
	for tool in dufs collie syncthing; do
		if [ -f "$ROOT_DIR/minime/ui/allium/dist/.allium/bin/$tool" ]; then
			cp "$ROOT_DIR/minime/ui/allium/dist/.allium/bin/$tool" "$STAGE_DIR/.allium/bin/$tool"
		else
			echo "WARNING: $tool binary not found — skipping injection" >&2
		fi
	done
	[ -d "$STATIC/.minime" ] && cp -r "$STATIC/.minime" "$STAGE_DIR/" || true

	OUT_TAR="$ROOT_DIR/minime/ui/out/allium-${LIBC}-aarch64.tar"
	tar -cf "$OUT_TAR" -C "$STAGE_DIR" .
	zstd -q -9 -f "$OUT_TAR"
	rm -f "$OUT_TAR"
	echo "Created ${OUT_TAR}.zst"

elif [ "$UI" = "muos" ]; then
	echo "Building muOS binaries for ${LIBC}..."
	cd "$ROOT_DIR/minime/ui/muos"

	if [ "$LIBC" = "musl" ]; then
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "cd /workspace/minime/ui/muos && make DEVICE=ARM64 BUILD=release DEBUG=1 CC=\"ccache gcc\" NM=\"nm\" -j\$(nproc) && chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/muos/bin"
	else
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "cd /workspace/minime/ui/muos && make DEVICE=ARM64 BUILD=release DEBUG=1 CROSS_COMPILE=\"aarch64-linux-gnu-\" CC=\"ccache aarch64-linux-gnu-gcc\" NM=\"aarch64-linux-gnu-nm\" -j\$(nproc) && chown -R \$(stat -c '%u:%g' /workspace) /workspace/minime/ui/muos/bin"
	fi

	STAGE_DIR=$(mktemp -d)
	mkdir -p "$STAGE_DIR/.muos/bin"
	mkdir -p "$STAGE_DIR/.muos/script"
	mkdir -p "$STAGE_DIR/.muos/share"
	mkdir -p "$STAGE_DIR/.minime"

	# Stage compiled binaries
	cp -r "$ROOT_DIR/minime/ui/muos/bin/." "$STAGE_DIR/.muos/bin/" 2>/dev/null || true

	# Stage scripts and share assets
	[ -d "$ROOT_DIR/minime/ui/muos/script" ] && cp -r "$ROOT_DIR/minime/ui/muos/script/." "$STAGE_DIR/.muos/script/" || true
	[ -d "$ROOT_DIR/minime/ui/muos/share" ] && cp -r "$ROOT_DIR/minime/ui/muos/share/." "$STAGE_DIR/.muos/share/" || true

	# Stage launcher and contract
	if [ -f "$ROOT_DIR/minime/ui/muos/launch.sh" ]; then
		cp "$ROOT_DIR/minime/ui/muos/launch.sh" "$STAGE_DIR/.muos/launch.sh"
		chmod +x "$STAGE_DIR/.muos/launch.sh"
	fi
	if [ -f "$ROOT_DIR/minime/ui/muos/.minime/ui.env" ]; then
		cp "$ROOT_DIR/minime/ui/muos/.minime/ui.env" "$STAGE_DIR/.minime/ui.env"
	fi

	# Inject shared Minime cores into RetroArch
	if [ -d "$ROOT_DIR/minime/build/cores/out" ]; then
		mkdir -p "$STAGE_DIR/.muos/emulator/retroarch/cores"
		cp "$ROOT_DIR/minime/build/cores/out/"*.so "$STAGE_DIR/.muos/emulator/retroarch/cores/" || true
	fi

	OUT_TAR="$ROOT_DIR/minime/ui/out/muos-${LIBC}-aarch64.tar"
	tar -cf "$OUT_TAR" -C "$STAGE_DIR" .
	zstd -q -9 -f "$OUT_TAR"
	rm -f "$OUT_TAR"
	echo "Created ${OUT_TAR}.zst"
else
	echo "Unknown UI: $UI" >&2
	exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
	chown -R "$USER:$USER" "$ROOT_DIR/minime/ui/out" 2>/dev/null || true
else
	sudo chown -R "$USER:$USER" "$ROOT_DIR/minime/ui/out" 2>/dev/null || true
fi

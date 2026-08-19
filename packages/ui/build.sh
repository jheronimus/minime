#!/bin/sh
set -eu

UI="${1:-}"
LIBC="${2:-}"

if [ -z "$UI" ] || [ -z "$LIBC" ]; then
	echo "Usage: $0 <ui> <libc>" >&2
	exit 1
fi

ROOT_DIR="$(pwd)"
mkdir -p "$ROOT_DIR/packages/ui/out"
OWNER="${GITHUB_REPOSITORY_OWNER:-jheronimus}"

if [ "$UI" = "minui" ]; then
	echo "Building MinUI binaries for ${LIBC}..."
	cd "$ROOT_DIR/packages/ui/minui"
	rm -rf releases build
	make setup

	if [ "$LIBC" = "musl" ]; then
		docker run --rm -u root \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			-v "$GITHUB_WORKSPACE:/workspace" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/packages/ui/minui/workspace && make CROSS_COMPILE=\"ccache \" PREFIX=/usr CC=\"ccache gcc\" CXX=\"ccache g++\" && cd .. && make CROSS_COMPILE=\"ccache \" PREFIX=/usr system PLATFORM=minime"
	else
		docker run --rm -u root \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			-v "$GITHUB_WORKSPACE:/workspace" \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "export UNION_PLATFORM=minime && cd /workspace/packages/ui/minui/workspace && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr CC=\"ccache aarch64-linux-gnu-gcc\" CXX=\"ccache aarch64-linux-gnu-g++\" && cd .. && make CROSS_COMPILE=\"aarch64-linux-gnu-\" PREFIX=/usr system PLATFORM=minime"
	fi

	# Inject the shared cores (built once by build-cores) into the paks. The
	# submodule `cores:` rule copies them from CORES_DIR into SYSTEM/minime/cores.
	make -C "$ROOT_DIR/packages/ui/minui" cores PLATFORM=minime \
		CORES_DIR="$ROOT_DIR/packages/cores/out"

	# Native PICO-8 (P8-NATIVE.pak + Splore.pak) launches the official glibc
	# pico8_64 binary (Raspberry Pi build). It cannot run on musl (Alpine),
	# so only ship it on glibc (Buildroot) builds.
	if [ "$LIBC" = "musl" ]; then
		echo "Skipping P8-NATIVE.pak + Splore.pak (require glibc) for ${LIBC} build..."
		rm -rf "$ROOT_DIR/packages/ui/minui/build/EXTRAS/Emus/minime/P8-NATIVE.pak"
		rm -rf "$ROOT_DIR/packages/ui/minui/build/EXTRAS/Tools/minime/Splore.pak"
	fi

	make package
	STAGE_DIR=$(mktemp -d)
	for zipfile in releases/*.zip; do
		[ -f "$zipfile" ] || continue
		unzip -q -o "$zipfile" -d "$STAGE_DIR"
	done
	cd "$ROOT_DIR"
	tar -cf "$ROOT_DIR/packages/ui/out/minui-${LIBC}-aarch64.tar" -C "$STAGE_DIR" .
	zstd -q -9 -f "$ROOT_DIR/packages/ui/out/minui-${LIBC}-aarch64.tar"
	rm -f "$ROOT_DIR/packages/ui/out/minui-${LIBC}-aarch64.tar"

elif [ "$UI" = "allium" ]; then
	echo "Building Allium binaries for ${LIBC}..."
	if [ "$LIBC" = "musl" ]; then
		TARGET="aarch64-unknown-linux-musl"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "cd /workspace/packages/ui/allium && cargo build --release --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            make retroarch-aarch64 CC=\"ccache gcc\" CXX=\"ccache g++\"; \
            make tools-aarch64; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/packages/ui/allium/target /workspace/packages/ui/allium/dist"

		mkdir -p packages/ui/allium/target/${TARGET}
		ln -sf ../release packages/ui/allium/target/${TARGET}/release
	else
		TARGET="aarch64-unknown-linux-gnu"
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.cargo/registry:/root/.cargo/registry" \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			-e CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "cd /workspace/packages/ui/allium && cargo build --release --target ${TARGET} --features minime \
            --bin alliumd --bin allium-launcher --bin allium-menu \
            --bin activity-tracker --bin screenshot --bin screenshot-viewer \
            --bin say --bin show; \
            make retroarch-aarch64 HOST=aarch64-linux-gnu CC=\"ccache aarch64-linux-gnu-gcc\" CXX=\"ccache aarch64-linux-gnu-g++\"; \
            make tools-aarch64 AARCH64_TARGET=aarch64-unknown-linux-gnu; \
            chown -R \$(stat -c '%u:%g' /workspace) /workspace/packages/ui/allium/target /workspace/packages/ui/allium/dist"
	fi

	BUILD="packages/ui/allium/target/${TARGET}/release"
	STATIC="packages/ui/allium/static"
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
	if [ -f "$ROOT_DIR/packages/ui/allium/dist/RetroArch/retroarch" ]; then
		cp "$ROOT_DIR/packages/ui/allium/dist/RetroArch/retroarch" "$STAGE_DIR/RetroArch/retroarch"
	else
		echo "WARNING: retroarch binary not found — skipping injection" >&2
	fi
	# Inject the shared Minime cores (built once by build-cores) into RetroArch.
	# Allium's retroarch launch.sh loads `-L RetroArch/.retroarch/cores/<name>_libretro.so`,
	# so the flat artifact goes straight in, overwriting the committed stock cores.
	if [ -d "$ROOT_DIR/packages/cores/out" ]; then
		mkdir -p "$STAGE_DIR/RetroArch/.retroarch/cores"
		cp "$ROOT_DIR/packages/cores/out/"*.so "$STAGE_DIR/RetroArch/.retroarch/cores/" || true
	else
		echo "WARNING: cores artifact not found — skipping core injection" >&2
	fi
	# Stage the .allium runtime tree (config/cores/locales/fonts/scripts/
	# migrations) plus the bundled aarch64 tools (dufs/collie/syncthing)
	# built by the tools-aarch64 target into .allium/bin.
	cp -r "$STATIC/.allium/." "$STAGE_DIR/.allium/" 2>/dev/null || true
	mkdir -p "$STAGE_DIR/.allium/bin"
	for tool in dufs collie syncthing; do
		if [ -f "$ROOT_DIR/packages/ui/allium/dist/.allium/bin/$tool" ]; then
			cp "$ROOT_DIR/packages/ui/allium/dist/.allium/bin/$tool" "$STAGE_DIR/.allium/bin/$tool"
		else
			echo "WARNING: $tool binary not found — skipping injection" >&2
		fi
	done
	[ -d "$STATIC/.minime" ] && cp -r "$STATIC/.minime" "$STAGE_DIR/" || true

	OUT_TAR="$ROOT_DIR/packages/ui/out/allium-${LIBC}-aarch64.tar"
	tar -cf "$OUT_TAR" -C "$STAGE_DIR" .
	zstd -q -9 -f "$OUT_TAR"
	rm -f "$OUT_TAR"
	echo "Created ${OUT_TAR}.zst"

elif [ "$UI" = "muos" ]; then
	echo "Building muOS binaries for ${LIBC}..."
	cd "$ROOT_DIR/packages/ui/muos/frontend"

	# Apply the Minime port patch series on top of the pristine upstream checkout.
	# Patches live in packages/ui/muos/patches (the fork is retired) and are
	# 3way-applied so they tolerate upstream drift.
	git apply --3way "$ROOT_DIR"/packages/ui/muos/patches/*.patch

	if [ "$LIBC" = "musl" ]; then
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.ui-ccache-musl:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-musl:latest" \
			/bin/bash -c "apk add --no-cache curl-dev sdl2_mixer-dev bzip2-dev xz-dev zstd-dev freetype-dev libpng-dev ffmpeg-dev && cd /workspace/packages/ui/muos/frontend && make DEVICE=ARM64 BUILD=release DEBUG=1 CC=\"ccache gcc\" NM=\"nm\" -j\$(nproc) && chown -R \$(stat -c '%u:%g' /workspace) /workspace/packages/ui/muos/frontend/bin"
	else
		docker run --rm -u root \
			-v "$GITHUB_WORKSPACE:/workspace" \
			-v "$HOME/.ui-ccache-glibc:/root/.ccache" \
			"ghcr.io/${OWNER}/minime-glibc:latest" \
			/bin/bash -c "apt-get update && apt-get install -y --no-install-recommends libssl-dev:arm64 libcurl4-openssl-dev:arm64 libsdl2-mixer-dev:arm64 libbz2-dev:arm64 liblzma-dev:arm64 libzstd-dev:arm64 libfreetype-dev:arm64 libpng-dev:arm64 libavformat-dev:arm64 libavcodec-dev:arm64 libavdevice-dev:arm64 libswresample-dev:arm64 libswscale-dev:arm64 libavutil-dev:arm64 && export CPATH=/usr/include/aarch64-linux-gnu && cd /workspace/packages/ui/muos/frontend && make DEVICE=ARM64 BUILD=release DEBUG=1 CROSS_COMPILE=\"aarch64-linux-gnu-\" CC=\"ccache aarch64-linux-gnu-gcc\" NM=\"aarch64-linux-gnu-nm\" -j\$(nproc) && chown -R \$(stat -c '%u:%g' /workspace) /workspace/packages/ui/muos/frontend/bin"
	fi

	STAGE_DIR=$(mktemp -d)
	mkdir -p "$STAGE_DIR/.muos/bin"
	mkdir -p "$STAGE_DIR/.muos/script"
	mkdir -p "$STAGE_DIR/.muos/share"
	mkdir -p "$STAGE_DIR/.minime"

	# Stage compiled binaries first, then restore the submodule to its pinned
	# pristine state (drop patches + build output, incl. gitignored bin/).
	cp -r "$ROOT_DIR/packages/ui/muos/frontend/bin/." "$STAGE_DIR/.muos/bin/" 2>/dev/null || true
	git reset -q --hard
	git clean -qfdx

	# Stage the MuOS runtime payload from the upstream internal submodule:
	# share/ (themes, fonts, info) and script/ (the runtime scripts the frontend
	# verifies by hash at boot). MuOS's own init/bin/device are NOT staged —
	# Minime replaces the init flow with launch.sh and derives device/config
	# from the device traits.
	# -L dereferences the symlinked fonts (muterm.ttf, mucredits.ttf) into real
	# files: the .muos payload lives on FAT32, which supports neither symlinks
	# nor hardlinks.
	[ -d "$ROOT_DIR/packages/ui/muos/internal/share" ] && cp -rL "$ROOT_DIR/packages/ui/muos/internal/share/." "$STAGE_DIR/.muos/share/" || true
	[ -d "$ROOT_DIR/packages/ui/muos/internal/script" ] && cp -r "$ROOT_DIR/packages/ui/muos/internal/script/." "$STAGE_DIR/.muos/script/" || true

	# Minime port overlay: launcher, ui.env contract, and iwd wifi scripts live
	# in packages/ui/muos/overlay (they are Minime-specific, not upstream).
	[ -f "$ROOT_DIR/packages/ui/muos/overlay/launch.sh" ] && cp "$ROOT_DIR/packages/ui/muos/overlay/launch.sh" "$STAGE_DIR/.muos/launch.sh"
	chmod +x "$STAGE_DIR/.muos/launch.sh" 2>/dev/null || true
	[ -f "$ROOT_DIR/packages/ui/muos/overlay/.packages/ui.env" ] && cp "$ROOT_DIR/packages/ui/muos/overlay/.packages/ui.env" "$STAGE_DIR/.packages/ui.env"
	cp -r "$ROOT_DIR/packages/ui/muos/overlay/script/." "$STAGE_DIR/.muos/script/" 2>/dev/null || true

	# Inject shared Minime cores into RetroArch
	if [ -d "$ROOT_DIR/packages/cores/out" ]; then
		mkdir -p "$STAGE_DIR/.muos/emulator/retroarch/cores"
		cp "$ROOT_DIR/packages/cores/out/"*.so "$STAGE_DIR/.muos/emulator/retroarch/cores/" || true
	fi

	OUT_TAR="$ROOT_DIR/packages/ui/out/muos-${LIBC}-aarch64.tar"
	# --dereference: internal/share ships symlinked fonts (muterm.ttf, mucredits.ttf)
	# that FAT32 cannot store; embed the target files instead.
	tar --dereference -cf "$OUT_TAR" -C "$STAGE_DIR" .
	zstd -q -9 -f "$OUT_TAR"
	rm -f "$OUT_TAR"
	echo "Created ${OUT_TAR}.zst"
else
	echo "Unknown UI: $UI" >&2
	exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
	chown -R "$USER:$USER" "$ROOT_DIR/packages/ui/out" 2>/dev/null || true
else
	sudo chown -R "$USER:$USER" "$ROOT_DIR/packages/ui/out" 2>/dev/null || true
fi

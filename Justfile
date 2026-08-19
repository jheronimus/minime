default: validate

# ── Validation gates (local-only; every check lives in scripts/) ──────────────

# Full gate: fast static checks + UI formatting (check-allium/minui/yabause
# need Rust + clang toolchains).
validate: validate-static check-allium check-minui check-yabause

# Fast static gate (no cargo/clang toolchains): what the pre-commit/pre-push
# hooks run. All validation logic is owned by scripts/check-*.sh.
validate-static: check-scripts check-workflows check-apkbuilds check-openrc check-traits check-kernel-config check-firmware check-patches check-package-lists check-git check-build-flow

# Validate Allium Rust code formatting (cargo fmt) and lints (cargo clippy)
check-allium:
    ./scripts/check-allium.sh

# Validate MinUI C code formatting (clang-format)
check-minui:
    ./scripts/check-minui.sh

# Validate YabaSanshiro libretro glue formatting (clang-format)
check-yabause:
    ./scripts/check-yabause.sh

# Validate GitHub Actions workflow files with actionlint
check-workflows:
    ./scripts/check-workflows.sh

# Validate merged kernel configuration fragments (duplicates, symbol format, vendor toggles)
check-kernel-config:
    ./scripts/check-kernel-config.sh

# Verify all required firmware files (CONFIG_EXTRA_FIRMWARE and DTS declarations) exist on disk
check-firmware:
    ./scripts/check-firmware.sh

# Verify all patch files are referenced in build manifests
check-patches:
    ./scripts/check-patches.sh

# Cross-check local package lists (Alpine ALPINE_PKGS/world-common, Buildroot
# common.config/external packages) so every referenced package is built.
check-package-lists:
    ./scripts/check-package-lists.sh

# ── Shell script validation ───────────────────────────────────────────────────

# Validate *.sh scripts: syntax (sh -n), shellcheck (auto-detect shell from
# shebang), and executable permission. Excludes upstream Buildroot tree.
check-scripts:
    ./scripts/check-scripts.sh

# Validate APKBUILD files: syntax (sh -n) and shellcheck targeting ash.
# SC2154 (abuild-injected vars) is suppressed via inline directive in each file.
# No shebang or executable check — abuild sources them directly.
check-apkbuilds:
    ./scripts/check-apkbuilds.sh

# Validate OpenRC init.d scripts: shellcheck targeting ash.
# SC2034 (openrc-run framework globals) is suppressed via inline directive.
# Executable permission is required — OpenRC runs them directly.
check-openrc:
    ./scripts/check-openrc.sh

# ── Other fast gates ──────────────────────────────────────────────────────────

# Validate device traits configuration
check-traits:
    ./scripts/check-traits.sh

# Check git diffs for whitespace errors and merge conflict markers
# (staged + working tree)
check-git:
    ./scripts/check-git.sh

# Enforce the build-convention rules (no compilation in packaging scripts,
# no packaging in build.sh) that the pipeline only catches at make time
check-build-flow:
    ./scripts/check-build-flow.sh

# ── Buildroot-dependent gates (require upstream Buildroot tree) ───────────────

# Run all gates (fast + Buildroot-dependent checks)
validate-ci: validate check-defconfigs check-packages

# Merge and validate our custom config fragments for all boards
check-defconfigs:
    make -C packages/components/buildroot defconfig BOARD=h700
    make -C packages/components/buildroot defconfig BOARD=rk3326
    make -C packages/components/buildroot defconfig BOARD=rk3566

# Lint our custom Buildroot packages using upstream check-package utility
check-packages:
    #!/usr/bin/env sh
    set -eu
    if [ -d packages/components/buildroot/buildroot ]; then
        python3 packages/components/buildroot/buildroot/utils/check-package -b packages/components/buildroot/external/package/*/*
    else
        echo "Buildroot source tree not found — skipping (requires upstream Buildroot tree)."
    fi

# ── UI Management ─────────────────────────────────────────────────────────────

# Build Allium UI binaries locally for target C library (musl or glibc)
build-allium target="musl":
    #!/usr/bin/env sh
    set -eu
    echo "Building Allium for target {{target}}..."
    cd packages/ui/allium
    if [ "{{target}}" = "musl" ]; then
        cargo build --release --target aarch64-unknown-linux-musl --features minime
    else
        cargo build --release --target aarch64-unknown-linux-gnu --features minime
    fi

# Build MinUI binaries locally for target C library (musl or glibc)
build-minui target="musl":
    #!/usr/bin/env sh
    set -eu
    echo "Building MinUI for target {{target}}..."
    cd packages/ui/minui
    make system PLATFORM=minime
    make cores PLATFORM=minime
    make package

# Build muOS binaries locally for target C library (musl or glibc)
build-muos target="musl":
    #!/usr/bin/env sh
    set -eu
    echo "Building muOS for target {{target}}..."
    ./packages/ui/build.sh muos {{target}}

# ── Developer setup ───────────────────────────────────────────────────────────

# Install git pre-commit/pre-push hooks that run `just validate-static` (the
# pre-push hook also forwards to git-lfs so LFS-tracked roms still upload).
install-hooks:
    ./scripts/install-hooks.sh

# ── Image Management ──────────────────────────────────────────────────────────

# Flash the latest testing image for a target to an SD card.
# Usage:
#   just deploy <os> <board> <ui> [disk_device]
#   just deploy ./path/to/minime-alpine-h700-minui.img  [disk_device]  (explicit image)
# Example:
#   just deploy alpine h700 minui
deploy os="" board="" ui="" disk_device="":
    #!/usr/bin/env sh
    set -eu

    target_image="{{os}}"
    if [ -z "${target_image}" ]; then
        echo "ERROR: No target or image specified." >&2
        echo "Usage: just deploy <os> <board> <ui> [disk] | just deploy <image> [disk]" >&2
        exit 1
    fi

    # If the first arg is an existing file (or looks like a path), treat it as
    # an explicit image; otherwise resolve the latest testing image by target.
    if [ -f "${target_image}" ] || [ "${target_image#/}" != "${target_image}" ] || [ "${target_image#./}" != "${target_image}" ]; then
        img_file="${target_image}"
    else
        [ -z "{{board}}" ] || [ -z "{{ui}}" ] && {
            echo "ERROR: deploy by target requires <os> <board> <ui>." >&2
            exit 1
        }
        asset="minime-{{os}}-{{board}}-{{ui}}.img.zst"
        img_file=$(./scripts/fetch-asset.sh "${asset}")
    fi

    target_device="{{disk_device}}"

    if [ -z "${target_device}" ]; then
        if [ ! -f "deploy.cfg" ]; then
            echo "ERROR: No disk device specified and deploy.cfg file not found." >&2
            echo "Copy deploy_sample.cfg to deploy.cfg or pass the device explicitly:" >&2
            echo "  just deploy {{os}} {{board}} {{ui}} /dev/rdiskN" >&2
            exit 1
        fi

        target_device=$(grep -E '^\s*disk_device=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
        if [ -z "${target_device}" ]; then
            echo "ERROR: deploy.cfg exists but does not specify a valid disk_device=" >&2
            exit 1
        fi

        # Guard: Only auto-deploy if disk contains a partition labeled 'minime'
        _base_chk=$(echo "${target_device}" | sed 's|/dev/r\{0,1\}disk|/dev/disk|')
        has_minime=""
        if command -v diskutil >/dev/null 2>&1; then
            has_minime=$(diskutil info "${_base_chk}s1" 2>/dev/null | grep -i "minime" || diskutil list "${_base_chk}" 2>/dev/null | grep -i "minime" || true)
        elif command -v lsblk >/dev/null 2>&1; then
            has_minime=$(lsblk -o LABEL "${_base_chk}" 2>/dev/null | grep -i "minime" || blkid "${_base_chk}"* 2>/dev/null | grep -i "minime" || true)
        fi

        if [ -z "${has_minime}" ]; then
            echo "ERROR: Target disk '${target_device}' in deploy.cfg does not contain a partition labeled 'minime'." >&2
            echo "Auto-deploy via deploy.cfg is restricted to previously flashed Minime cards." >&2
            echo "To flash a fresh card, specify the target disk explicitly:" >&2
            echo "  just deploy {{os}} {{board}} {{ui}} ${target_device}" >&2
            exit 1
        fi
    fi

    if [ ! -f "${img_file}" ] && [ ! -f "${img_file%.zst}" ]; then
        echo "ERROR: Image file '${img_file}' not found" >&2
        exit 1
    fi

    _base=$(echo "${target_device}" | sed 's|/dev/r\{0,1\}disk|/dev/disk|')
    device="${_base}"
    rdevice=$(echo "${_base}" | sed 's|/dev/disk|/dev/rdisk|')

    echo "Unmounting target disk: ${device}..."
    diskutil unmountDisk force "${device}" 2>/dev/null || true

    echo "Writing image to ${device}..."
    if [ ! -f "${img_file}" ] && [ -f "${img_file%.zst}" ]; then
        img_file="${img_file%.zst}"
    fi

    case "${img_file}" in
        *.zst)
            if ! (unzstd -c "${img_file}" | sudo dd of="${rdevice}" bs=1m status=progress); then
                echo "Raw device write interrupted; retrying on block device ${device}..."
                diskutil unmountDisk force "${device}" 2>/dev/null || true
                unzstd -c "${img_file}" | sudo dd of="${device}" bs=1m status=progress
            fi
            ;;
        *)
            if ! sudo dd if="${img_file}" of="${rdevice}" bs=1m status=progress; then
                echo "Raw device write interrupted; retrying on block device ${device}..."
                diskutil unmountDisk force "${device}" 2>/dev/null || true
                sudo dd if="${img_file}" of="${device}" bs=1m status=progress
            fi
            ;;
    esac

    if [ -f wifi.cfg ]; then
        echo "wifi.cfg found! Mount disk to apply Wi-Fi settings..."
        diskutil mountDisk "${device}" 2>/dev/null || true
        diskutil mount "${device}s1" 2>/dev/null || true
        sleep 2

        # Find partition mount point dynamically
        mount_point=$(mount | grep -E "^${device}s[0-9]+" | head -n 1 | sed 's/.* on //' | sed 's/ (.*//')
        if [ -z "${mount_point}" ]; then
            mount_point=$(mount | grep -i 'minime' | head -n 1 | sed 's/.* on //' | sed 's/ (.*//')
        fi

        if [ -n "${mount_point}" ] && [ -d "${mount_point}" ]; then
            echo "Mounted at: ${mount_point}"
            mkdir -p "${mount_point}/.minime/config/iwd"
            mkdir -p "${mount_point}/.minime/config/wifi"
            echo 1 > "${mount_point}/.minime/config/wifi/enabled"
            cp -f wifi.cfg "${mount_point}/.minime/config/wifi.cfg"

            # Generate native iwd .psk profiles
            ssid=""
            psk=""
            while IFS='=' read -r key val || [ -n "$key" ]; do
                [ -n "$key" ] || continue
                key=$(printf '%s' "$key" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                val=$(printf '%s' "$val" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
                case "$key" in
                    \#*) continue ;;
                    SSID)
                        if [ -n "$ssid" ]; then
                            if [ -n "$psk" ]; then
                                printf '[Security]\nPassphrase=%s\n[Settings]\nAutoConnect=true\n' "$psk" > "${mount_point}/.minime/config/iwd/${ssid}.psk"
                            else
                                printf '[Settings]\nAutoConnect=true\n' > "${mount_point}/.minime/config/iwd/${ssid}.psk"
                            fi
                            psk=""
                        fi
                        ssid="$val"
                        ;;
                    Passphrase) psk="$val" ;;
                esac
            done < wifi.cfg
            if [ -n "$ssid" ]; then
                if [ -n "$psk" ]; then
                    printf '[Security]\nPassphrase=%s\n[Settings]\nAutoConnect=true\n' "$psk" > "${mount_point}/.minime/config/iwd/${ssid}.psk"
                else
                    printf '[Settings]\nAutoConnect=true\n' > "${mount_point}/.minime/config/iwd/${ssid}.psk"
                fi
            fi
            echo "Wi-Fi configuration and iwd profiles applied successfully."
        else
            echo "WARNING: Could not find mount point. Wi-Fi settings not applied." >&2
        fi
    fi

    echo "Flushing buffers and ejecting ${device}..."
    sync
    diskutil unmountDisk "${device}" 2>/dev/null || true
    diskutil eject "${device}" 2>/dev/null || true
    echo "Deployment complete!"

    # Push desktop notification (OSC 9) and audio bell chime (\a)
    printf '\033]9;Minime: Deployment Complete (%s)\007\a' "${device}" 2>/dev/null || true

# Run a shell command on the target device (SSH by default; pass --telnet first to force telnet)
# Usage:
#   just shell "ps aux" [ip]
#   just shell --telnet "ps aux"
shell cmd="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    printf '%s\n' '{{cmd}}' > "$tmp"
    export REMOTE_CMD_FILE="$tmp"
    ./scripts/remote-cmd.sh "{{ip}}"
    rm -f "$tmp"

# OTA-update the device to a UI (minui | allium | muos). For muos, if the
# installed on-device updater predates muos support, bootstraps through a
# supported UI first to pull the current OS, then switches to muos.
# Usage:
#   just ota <ui> [ip]
ota ui="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ui="{{ui}}"
    case "$ui" in
      minui|allium|muos) ;;
      *) echo "ERROR: unknown UI '$ui' (expected minui, allium, or muos)" >&2; exit 1 ;;
    esac
    ip="{{ip}}"
    if [ "$ui" = "muos" ] && ! just shell "grep -q muos /usr/bin/update.sh" "$ip" 2>/dev/null; then
        echo "Installed updater predates muos support; bootstrapping via minui first..."
        just shell "update.sh minui" "$ip"
        for i in $(seq 1 30); do
            sleep 10
            just shell "grep -q muos /usr/bin/update.sh" "$ip" 2>/dev/null && break
        done
        just shell "grep -q muos /usr/bin/update.sh" "$ip" 2>/dev/null || { echo "ERROR: bootstrap did not install a muos-capable updater" >&2; exit 1; }
    fi
    just shell "update.sh $ui" "$ip"

# Copy a file to the target device (scp/SSH by default, writes any path as root;
# pass --ftp first to use FTP, which is limited to the /mnt/sdcard root)
# Usage:
#   just upload <local_file> [remote_path] [ip]
#   just upload --ftp <local_file> [remote_filename] [ip]
upload file="" remote="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    MODE="scp"; F=""; R=""; I=""
    for a in "{{file}}" "{{remote}}" "{{ip}}"; do
        if [ "$a" = "--ftp" ]; then MODE="ftp"; continue; fi
        if [ -z "$F" ]; then F="$a"; continue; fi
        if [ -z "$R" ]; then R="$a"; continue; fi
        I="$a"
    done
    if [ "$MODE" = "ftp" ]; then
        ./scripts/remote-upload.sh "$F" "$R" "$I"
    else
        ./scripts/scp-upload.sh "$F" "$R" "$I"
    fi

# Fetch a diagnostics bundle from the target device (logs + dmesg + config)
# Usage:
#   just get-logs [ip]
get-logs ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/get-logs.sh "{{ip}}"

# Capture a live screenshot from the target device without disk writes
# Usage:
#   just screenshot [output_path] [ip]
screenshot out="screenshot.png" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/remote-screenshot.sh "{{out}}" "{{ip}}"

# Simulate a key press on target device
# Usage:
#   just press <key> [duration_ms] [ip]
press key duration="50" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/remote-cmd.sh "remote press {{key}} --duration {{duration}}" "{{ip}}"

# Simulate a timed key sequence on target device
# Usage:
#   just key-seq "<sequence>" [ip]
key-seq sequence ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/remote-cmd.sh "remote sequence '{{sequence}}'" "{{ip}}"

# Run on-device performance benchmark suite
# Usage:
#   just benchmark [args] [ip]
#   just benchmark "--quick"
#   just benchmark "--save /mnt/sdcard/baseline.json"
#   just benchmark "--compare /mnt/sdcard/baseline.json"
benchmark args="--all" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/remote-cmd.sh "benchmark {{args}}" "{{ip}}"

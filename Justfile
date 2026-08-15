default: validate

# ── Fast gates (run pre-commit and in CI) ─────────────────────────────────────

# Run all fast quality gates (shell validation, workflows, traits, git hygiene, kernel config, firmware, patches, hashes, UI submodules)
validate: check-scripts check-workflows check-apkbuilds check-openrc check-traits check-kernel-config check-firmware check-patches check-hashes check-git check-build-flow check-allium check-minui check-yabause

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
    mise exec -- actionlint

# Validate merged kernel configuration fragments (duplicates, symbol format, vendor toggles)
check-kernel-config:
    ./scripts/check-kernel-config.sh

# Verify all required firmware files (CONFIG_EXTRA_FIRMWARE and DTS declarations) exist on disk
check-firmware:
    ./scripts/check-firmware.sh

# Verify all patch files are referenced in build manifests
check-patches:
    ./scripts/check-patches.sh

# Validate SHA-256 and SHA-512 hash formats in package manifests
check-hashes:
    ./scripts/check-hashes.sh

# ── Shell script validation ───────────────────────────────────────────────────

# Validate *.sh scripts: syntax (sh -n), shellcheck (auto-detect shell from
# shebang), and executable permission.  Excludes upstream Buildroot tree.
check-scripts:
    #!/usr/bin/env sh
    set -eu
    failed=0
    find . -type f -name "*.sh" \
        -not -path "*/buildroot/buildroot/*" \
        -not -path "*/build-bootloader-tmp/*" \
        -not -path "*/ui/*" \
        -not -path "*/.git/*" \
        -not -path "*/pkg/*" \
        -not -path "*/downloads/*" \
        -not -path "*/src/yabause/libchdr/*" \
        -not -path "*/src/yabause/yabause/*" \
        | sort | while read -r f; do
        echo "  sh: $f"
        # Syntax-check with the interpreter declared by the shebang: sh cannot
        # parse bash scripts (arrays, here-strings), bash rejects sh-only -e/-u
        # is fine, but bash-specific constructs must not be run through sh.
        interpreter=$(head -n 1 "$f" | sed -n 's|^#!.*[ /]\([a-zA-Z0-9._-]*\) *$|\1|p' | head -n 1)
        case "$interpreter" in
        bash) bash -n "$f" ;;
        *) sh -n "$f" ;;
        esac
        shellcheck --severity=warning "$f"
        if head -n 1 "$f" | grep -q "^#!"; then
            if [ ! -x "$f" ]; then
                echo "ERROR: $f has a shebang but no executable bit" >&2
                exit 1
            fi
        fi
    done

# Validate APKBUILD files: syntax (sh -n) and shellcheck targeting ash.
# SC2154 (abuild-injected vars) is suppressed via inline directive in each file.
# No shebang or executable check — abuild sources them directly.
check-apkbuilds:
    #!/usr/bin/env sh
    set -eu
    find minime/targets/alpine/aports -name "APKBUILD" -not -path "*/pkg/*" | sort | while read -r f; do
        echo "  apkbuild: $f"
        sh -n "$f"
        shellcheck --shell=sh --severity=warning "$f"
    done

# Validate OpenRC init.d scripts: shellcheck targeting ash.
# SC2034 (openrc-run framework globals) is suppressed via inline directive.
# Executable permission is required — OpenRC runs them directly.
check-openrc:
    #!/usr/bin/env sh
    set -eu
    find minime/boards -path "*/etc/init.d/*" -type f \
        -not -path "*/pkg/*" \
        | sort | while read -r f; do
        echo "  openrc: $f"
        shellcheck --shell=sh --severity=warning "$f"
        if [ ! -x "$f" ]; then
            echo "ERROR: $f is not executable" >&2
            exit 1
        fi
    done

# ── Other fast gates ──────────────────────────────────────────────────────────

# Validate device traits configuration
check-traits:
    ./scripts/check-traits.sh

# Check git diff for whitespace errors and merge conflict markers
check-git:
    git diff --check

# Validate build flow convention: build.sh + genimage.sh + Makefile pattern
check-build-flow:
    #!/usr/bin/env sh
    set -eu
    failed=0

    # 1. build.sh exists for each target
    for target in alpine buildroot; do
        script="minime/targets/${target}/scripts/build.sh"
        if [ ! -f "$script" ]; then
            echo "ERROR: $script missing" >&2
            failed=1
        fi
    done

    # 2. build.sh has 'components' subcommand
    for target in alpine buildroot; do
        script="minime/targets/${target}/scripts/build.sh"
        if [ -f "$script" ] && ! grep -q 'components' "$script"; then
            echo "ERROR: $script missing 'components' subcommand" >&2
            failed=1
        fi
    done

    # 3. mkimage.sh exists and doesn't contain compilation logic
    mkimage="minime/build/mkimage.sh"
    if [ ! -f "$mkimage" ]; then
        echo "ERROR: $mkimage missing" >&2
        failed=1
    elif grep -qE '^\s*(make |gcc |g\+\+ |configure |cmake |abuild |apk add)' "$mkimage"; then
        echo "ERROR: $mkimage contains compilation logic" >&2
        failed=1
    fi

    # 4. Makefiles have 'components' target, and common.mk has 'image' target
    common_mk="minime/targets/common.mk"
    if [ ! -f "$common_mk" ]; then
        echo "ERROR: $common_mk missing" >&2
        failed=1
    elif ! grep -q '^image:' "$common_mk" && ! grep -q '^image ' "$common_mk"; then
        echo "ERROR: $common_mk missing 'image' target" >&2
        failed=1
    fi

    for target in alpine buildroot; do
        mk="minime/targets/${target}/Makefile"
        if [ -f "$mk" ]; then
            if ! grep -q '^components:' "$mk" && ! grep -q '^components ' "$mk"; then
                echo "ERROR: $mk missing 'components' target" >&2
                failed=1
            fi
        fi
    done

    if [ "$failed" -eq 0 ]; then
        echo "Build flow convention check passed."
    else
        exit 1
    fi

# ── CI-only gates (require upstream Buildroot tree) ───────────────────────────

# Run all CI gates (fast gates + Buildroot-dependent checks)
validate-ci: validate check-defconfigs check-packages

# Merge and validate our custom config fragments for all boards
check-defconfigs:
    make -C minime/targets/buildroot defconfig BOARD=h700
    make -C minime/targets/buildroot defconfig BOARD=rk3326
    make -C minime/targets/buildroot defconfig BOARD=rk3566

# Lint our custom Buildroot packages using upstream check-package utility
check-packages:
    #!/usr/bin/env sh
    set -eu
    if [ -d minime/targets/buildroot/buildroot ]; then
        python3 minime/targets/buildroot/buildroot/utils/check-package -b minime/targets/buildroot/external/package/*/*
    else
        echo "Buildroot source tree not found — skipping (CI only)."
    fi

# ── UI Management ─────────────────────────────────────────────────────────────

# Build Allium UI binaries locally for target C library (musl or glibc)
build-allium target="musl":
    #!/usr/bin/env sh
    set -eu
    echo "Building Allium for target {{target}}..."
    cd minime/ui/allium
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
    cd minime/ui/minui
    make system PLATFORM=minime
    make cores PLATFORM=minime
    make package

# ── Developer setup ───────────────────────────────────────────────────────────

# Install git pre-commit hook that runs `just validate` before every commit
install-hooks:
    #!/usr/bin/env sh
    set -eu
    hook=".git/hooks/pre-commit"
    printf '#!/usr/bin/env sh\n# Auto-installed by `just install-hooks`. Run `just validate` manually.\nset -eu\necho "==> pre-commit: running just validate"\nexec just validate\n' > "$hook"
    chmod +x "$hook"
    echo "Installed pre-commit hook at $hook"

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
            mkdir -p "${mount_point}/.minime/config"
            cp -f wifi.cfg "${mount_point}/.minime/config/wifi.cfg"
            echo "Wi-Fi configuration applied successfully."
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

# Execute a remote shell command on target device (SSH if dropbear is up, else telnet)
# Usage:
#   just remote "ps aux" [ip]
remote cmd="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    printf '%s\n' '{{cmd}}' > "$tmp"
    export REMOTE_CMD_FILE="$tmp"
    ./scripts/remote-cmd.sh "{{ip}}"
    rm -f "$tmp"

# Execute a remote shell command on target device over SSH (dropbear, blank-password root)
# Usage:
#   just rsh "ps aux" [ip]
rsh cmd="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    printf '%s\n' '{{cmd}}' > "$tmp"
    export REMOTE_CMD_FILE="$tmp"
    ./scripts/ssh-cmd.sh "{{ip}}"
    rm -f "$tmp"

# Upload a file to target device over FTP
# Usage:
#   just upload <file> [remote_filename] [ip]
upload file="" remote_filename="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/remote-upload.sh "{{file}}" "{{remote_filename}}" "{{ip}}"

# Copy a local file to target device over SSH/scp (can write any path as root)
# Usage:
#   just scp <local_file> <remote_path> [ip]
scp file="" remote="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/scp-upload.sh "{{file}}" "{{remote}}" "{{ip}}"

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

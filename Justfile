default: validate

# ── Fast gates (run pre-commit and in CI) ─────────────────────────────────────

# Run all fast quality gates (shell validation, workflows, traits, git hygiene, kernel config, firmware, patches, hashes, UI submodules)
validate: check-scripts check-workflows check-apkbuilds check-openrc check-traits check-kernel-config check-firmware check-patches check-hashes check-git check-build-flow check-allium check-minui

# Validate Allium Rust code formatting (cargo fmt) and lints (cargo clippy)
check-allium:
    ./scripts/check-allium.sh

# Validate MinUI C code formatting (clang-format)
check-minui:
    ./scripts/check-minui.sh

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
        -not -path "*/ui/*" \
        -not -path "*/.git/*" \
        -not -path "*/pkg/*" \
        | sort | while read -r f; do
        echo "  sh: $f"
        sh -n "$f"
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

# Fetch testing images. Use "all" for any slot to match all options.
# Examples: just fetch alpine rk3566 all    just fetch all    just fetch all all minui
fetch os="all" board="all" ui="all":
    #!/usr/bin/env sh
    set -eu

    os_val="{{os}}"
    board_val="{{board}}"
    ui_val="{{ui}}"

    os_regex="${os_val}"
    [ "$os_val" = "all" ] && os_regex="[^-]+"
    
    board_regex="${board_val}"
    [ "$board_val" = "all" ] && board_regex="[^-]+"
    
    ui_regex="${ui_val}"
    [ "$ui_val" = "all" ] && ui_regex="[^-]+"

    pattern="^minime-${os_regex}-${board_regex}-${ui_regex}\.img\.xz$"

    echo "Querying available testing releases from GitHub..."
    available_assets=$(curl -sL https://api.github.com/repos/jheronimus/minime/releases/tags/testing | grep -o '"name": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' || true)

    images=$(echo "$available_assets" | grep -E "$pattern" || true)

    if [ -z "$images" ]; then
        echo "ERROR: These images are currently not available in the testing release (os=${os_val} board=${board_val} ui=${ui_val})." >&2
        exit 1
    fi

    echo "Images to fetch:"
    for img in $images; do
        echo "  ${img}"
    done
    echo ""

    # Download
    mkdir -p downloads
    downloaded=""
    for img in $images; do
        url="https://github.com/jheronimus/minime/releases/download/testing/${img}"
        dest="downloads/${img}"
        img_decompressed="downloads/${img%.xz}"

        rm -f "${dest}"

        if command -v aria2c >/dev/null 2>&1; then
            echo "Fetching ${img} using aria2 (10 parallel connections)..."
            aria2c -x10 -s10 -k1m --console-log-level=warn --summary-interval=0 --allow-overwrite=true -d downloads -o "${img}" "${url}"
        else
            echo "Fetching ${img}..."
            curl -L --fail --show-error --progress-bar "${url}" -o "${dest}"
        fi

        echo "Decompressing to ${img_decompressed}..."
        xz -d -f "${dest}"
        echo "Success! Image saved to ${img_decompressed}"
        downloaded="${downloaded:+$downloaded }$img_decompressed"
    done

    # Desktop notification
    img_count=$(echo "$downloaded" | wc -w | tr -d ' ')
    printf '\033]9;Minime: Download Complete (%s images)\007\a' "$img_count" 2>/dev/null || true

    # Flash phase (interactive only)
    if [ -t 0 ] && [ -n "$downloaded" ]; then
        if [ "$img_count" -eq 1 ]; then
            printf "Deploy image %s to SD card? [y/N] " "$downloaded"
            read -r ans
            case "$ans" in
                y|Y|yes|YES) just deploy "$downloaded" ;;
                *) echo "Skipping deployment." ;;
            esac
        else
            while true; do
                echo ""
                echo "Downloaded images:"
                i=1
                for img in $downloaded; do
                    printf "  %s) %s\n" "$i" "$img"
                    i=$((i + 1))
                done
                none_option=$i
                printf "  %s) None (skip)\n" "$none_option"
                echo ""
                printf "Which image to flash? [1-%s] " "$none_option"
                read -r choice

                if [ -z "$choice" ] || [ "$choice" -eq "$none_option" ]; then
                    echo "Skipping deployment."
                    break
                fi

                if ! printf '%s' "$choice" | grep -qE '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "$img_count" ]; then
                    echo "Invalid choice. Please enter 1-${none_option}."
                    continue
                fi

                selected_img=$(echo "$downloaded" | cut -d' ' -f"$choice")
                just deploy "$selected_img"

                printf "Flash another image? [y/N] "
                read -r ans
                case "$ans" in
                    y|Y|yes|YES) continue ;;
                    *) break ;;
                esac
            done
        fi
    fi

# Fetch testing update packages (.tar.xz). Use "all" for any slot to match all options.
# Examples: just fetch-update alpine rk3566 all
fetch-update os="all" board="all" ui="all":
    #!/usr/bin/env sh
    set -eu

    os_val="{{os}}"
    board_val="{{board}}"
    ui_val="{{ui}}"

    os_regex="${os_val}"
    [ "$os_val" = "all" ] && os_regex="[^-]+"
    
    board_regex="${board_val}"
    [ "$board_val" = "all" ] && board_regex="[^-]+"
    
    ui_regex="${ui_val}"
    [ "$ui_val" = "all" ] && ui_regex="[^-]+"

    pattern="^minime-${os_regex}-${board_regex}-${ui_regex}\.tar\.xz$"

    echo "Querying available testing updates from GitHub..."
    available_assets=$(curl -sL https://api.github.com/repos/jheronimus/minime/releases/tags/testing | grep -o '"name": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' || true)

    updates=$(echo "$available_assets" | grep -E "$pattern" || true)

    if [ -z "$updates" ]; then
        echo "ERROR: These update packages are currently not available in the testing release (os=${os_val} board=${board_val} ui=${ui_val})." >&2
        exit 1
    fi

    echo "Update packages to fetch:"
    for pkg in $updates; do
        echo "  ${pkg}"
    done
    echo ""

    mkdir -p downloads
    downloaded=""
    for pkg in $updates; do
        url="https://github.com/jheronimus/minime/releases/download/testing/${pkg}"
        dest="downloads/${pkg}"

        rm -f "${dest}"

        if command -v aria2c >/dev/null 2>&1; then
            echo "Fetching ${pkg} using aria2..."
            aria2c -x10 -s10 -k1m --console-log-level=warn --summary-interval=0 --allow-overwrite=true -d downloads -o "${pkg}" "${url}"
        else
            echo "Fetching ${pkg}..."
            curl -L --fail --show-error --progress-bar "${url}" -o "${dest}"
        fi

        echo "Success! Update package saved to ${dest}"
        downloaded="${downloaded:+$downloaded }${dest}"
    done

    echo ""
    echo "Downloaded update archives:"
    for d in $downloaded; do
        echo "  $d"
    done


# Deploy a firmware image to a target disk device
deploy image disk_device="":
    #!/usr/bin/env sh
    set -eu
    if [ ! -f "{{image}}" ]; then
        echo "ERROR: Image file '{{image}}' not found" >&2
        exit 1
    fi

    target_device="{{disk_device}}"

    if [ -z "${target_device}" ]; then
        if [ ! -f "deploy.cfg" ]; then
            echo "ERROR: No disk device specified and deploy.cfg file not found." >&2
            echo "Copy deploy_sample.cfg to deploy.cfg or pass the device explicitly:" >&2
            echo "  just deploy {{image}} /dev/rdiskN" >&2
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
            echo "  just deploy {{image}} ${target_device}" >&2
            exit 1
        fi
    fi

    _base=$(echo "${target_device}" | sed 's|/dev/r\{0,1\}disk|/dev/disk|')
    device="${_base}"
    rdevice=$(echo "${_base}" | sed 's|/dev/disk|/dev/rdisk|')

    echo "Unmounting target disk: ${device}..."
    diskutil unmountDisk force "${device}" 2>/dev/null || true

    echo "Writing image to ${device}..."
    img_file="{{image}}"
    if [ ! -f "${img_file}" ] && [ -f "${img_file%.xz}" ]; then
        img_file="${img_file%.xz}"
    fi

    case "${img_file}" in
        *.xz)
            if ! (xz -dc "${img_file}" | sudo dd of="${rdevice}" bs=1m status=progress); then
                echo "Raw device write interrupted; retrying on block device ${device}..."
                diskutil unmountDisk force "${device}" 2>/dev/null || true
                xz -dc "${img_file}" | sudo dd of="${device}" bs=1m status=progress
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

# Deliver an OTA update payload to target device over network (FTP/telnet)
# Usage:
#   just update [package] [ip]
update package="" ip="":
    #!/usr/bin/env bash
    set -euo pipefail

    target_ip="{{ip}}"
    if [ -z "${target_ip}" ]; then
        if [ -f "deploy.cfg" ]; then
            target_ip=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
        fi
    fi

    if [ -z "${target_ip}" ]; then
        echo "ERROR: No target IP specified and target_ip not found in deploy.cfg." >&2
        echo "Usage: just update [package] [ip]" >&2
        exit 1
    fi

    target_pkg="{{package}}"
    if [ -z "${target_pkg}" ]; then
        target_pkg=$(find minime/ui/minui/releases/ -name "MinUI-*-base.zip" 2>/dev/null | sort -V | tail -n1 || true)
    fi

    if [ -z "${target_pkg}" ] || [ ! -f "${target_pkg}" ]; then
        echo "ERROR: Update package '${target_pkg}' not found." >&2
        exit 1
    fi

    ./scripts/update-device.sh "${target_pkg}" "${target_ip}"

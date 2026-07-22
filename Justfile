default: validate

# ── Fast gates (run pre-commit and in CI) ─────────────────────────────────────

# Run all fast quality gates (shell validation, traits, git hygiene, kernel config, firmware, patches, hashes)
validate: check-scripts check-apkbuilds check-openrc check-openrc-deps check-traits check-kernel-config check-firmware check-patches check-hashes check-git

# Validate merged kernel configuration fragments (duplicates, symbol format, vendor toggles)
check-kernel-config:
    ./scripts/check-kernel-config.py

# Verify all required firmware files (CONFIG_EXTRA_FIRMWARE and DTS declarations) exist on disk
check-firmware:
    ./scripts/check-firmware.py

# Verify all patch files are referenced in build manifests
check-patches:
    ./scripts/check-patches.py

# Validate SHA-256 and SHA-512 hash formats in package manifests
check-hashes:
    ./scripts/check-hashes.py

# Validate OpenRC service dependency resolution
check-openrc-deps:
    ./scripts/check-openrc-deps.py

# ── Shell script validation ───────────────────────────────────────────────────

# Validate *.sh scripts: syntax (sh -n), shellcheck (auto-detect shell from
# shebang), and executable permission.  Excludes upstream Buildroot tree.
check-scripts:
    #!/usr/bin/env sh
    set -eu
    failed=0
    find . -type f -name "*.sh" \
        -not -path "*/buildroot/buildroot/*" \
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
    find alpine/aports -name "APKBUILD" -not -path "*/pkg/*" | sort | while read -r f; do
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
    find alpine/aports -path "*/files/etc/init.d/*" -type f \
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
    ./alpine/board/common/check-traits.sh

# Check git diff for whitespace errors and merge conflict markers
check-git:
    git diff --check

# ── CI-only gates (require upstream Buildroot tree) ───────────────────────────

# Run all CI gates (fast gates + Buildroot-dependent checks)
validate-ci: validate check-defconfigs check-packages

# Merge and validate our custom config fragments for all boards
check-defconfigs:
    make -C buildroot defconfig BOARD=h700
    make -C buildroot defconfig BOARD=rk3326
    make -C buildroot defconfig BOARD=rk3566

# Lint our custom Buildroot packages using upstream check-package utility
check-packages:
    #!/usr/bin/env sh
    set -eu
    if [ -d buildroot/buildroot ]; then
        python3 buildroot/buildroot/utils/check-package buildroot/external/package/*/*
    else
        echo "Buildroot source tree not found — skipping (CI only)."
    fi

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

# Fetch the latest testing image for a specific OS, board, and UI option
fetch os board ui:
    #!/usr/bin/env sh
    set -eu
    case "{{os}}" in
        alpine|buildroot) ;;
        *) echo "ERROR: OS must be 'alpine' or 'buildroot'" >&2; exit 1 ;;
    esac
    case "{{board}}" in
        h700|rk3326|rk3566) ;;
        *) echo "ERROR: board must be 'h700', 'rk3326', or 'rk3566'" >&2; exit 1 ;;
    esac
    case "{{ui}}" in
        minui|allium) ;;
        *) echo "ERROR: UI must be 'minui' or 'allium'" >&2; exit 1 ;;
    esac

    if [ "{{os}}" = "alpine" ]; then
        filename="minime-alpine-{{board}}-{{ui}}.img.xz"
    else
        filename="minime-buildroot-{{board}}-{{ui}}.img.xz"
    fi

    url="https://github.com/jheronimus/minime/releases/download/testing/${filename}"
    mkdir -p downloads
    dest="downloads/${filename}"
    img="downloads/${filename%.xz}"

    echo "Fetching ${filename}..."
    curl -L --fail --show-error --progress-bar "${url}" -o "${dest}"

    echo "Decompressing to ${img}..."
    xz -d -f "${dest}"
    echo "Success! Image saved to ${img}"

    if [ -t 0 ]; then
        printf "Deploy image %s to SD card? [y/N] " "${img}"
        read -r ans
        case "${ans}" in
            y|Y|yes|YES)
                just deploy "${img}"
                ;;
            *)
                echo "Skipping deployment."
                ;;
        esac
    fi

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

        target_device=$(grep -E '^\s*disk_device=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\'\r')
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

    echo "Ejecting ${device}..."
    diskutil eject "${device}" 2>/dev/null || true
    echo "Deployment complete!"

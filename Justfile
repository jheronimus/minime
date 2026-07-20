default: validate

# ── Fast gates (run pre-commit and in CI) ─────────────────────────────────────

# Run all fast quality gates (shell validation, traits, git hygiene)
validate: check-scripts check-apkbuilds check-openrc check-traits check-git

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

# Fetch the latest nightly image for a specific OS, board, and UI option
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

    url="https://github.com/jheronimus/minime/releases/download/nightly/${filename}"
    mkdir -p downloads
    dest="downloads/${filename}"
    img="downloads/${filename%.xz}"

    echo "Fetching ${filename}..."
    curl -L --fail --show-error --progress-bar "${url}" -o "${dest}"

    echo "Decompressing to ${img}..."
    xz -d -f "${dest}"
    echo "Success! Image saved to ${img}"

# Deploy a firmware image to a target disk device
deploy image disk_device:
    #!/usr/bin/env sh
    set -eu
    if [ ! -f "{{image}}" ]; then
        echo "ERROR: Image file '{{image}}' not found" >&2
        exit 1
    fi

    device="{{disk_device}}"
    case "${device}" in
        /dev/disk*|/dev/rdisk*) ;;
        *) echo "ERROR: device must start with /dev/disk or /dev/rdisk" >&2; exit 1 ;;
    esac

    # Use raw device (/dev/rdiskN) for significantly faster write speeds on macOS
    rdevice=$(echo "${device}" | sed 's|/dev/disk|/dev/rdisk|')

    echo "Unmounting target disk: ${device}..."
    diskutil unmountDisk "${device}"

    echo "Writing image to ${rdevice}..."
    sudo dd if="{{image}}" of="${rdevice}" bs=1m status=progress

    if [ -f wifi.cfg ]; then
        echo "wifi.cfg found! Mount disk to apply Wi-Fi settings..."
        diskutil mountDisk "${device}"
        sleep 2

        # Find partition mount point dynamically
        mount_point=$(mount | grep -E "^${device}s[0-9]+" | head -n 1 | awk -F ' on ' '{print $2}' | awk -F ' \(' '{print $1}')
        if [ -z "${mount_point}" ]; then
            mount_point=$(mount | grep -i 'minime' | head -n 1 | awk -F ' on ' '{print $2}' | awk -F ' \(' '{print $1}')
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
    diskutil eject "${device}"
    echo "Deployment complete!"

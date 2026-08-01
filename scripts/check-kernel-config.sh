#!/bin/bash
# Check kernel configuration fragments for duplicates and missing vendors
# Max SLOC: 100

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

errors=0
warnings=0

CONFIG_PAIRS=(
    "h700 minime/boards/common/tiny-base.config minime/boards/h700/tiny-h700.config"
    "rk3326 minime/boards/common/tiny-base.config minime/boards/rk3326/tiny-rk3326.config"
    "rk3566 minime/boards/common/tiny-base.config minime/boards/rk3566/tiny-rk3566.config"
)

echo "Checking kernel configuration fragments..."

for pair in "${CONFIG_PAIRS[@]}"; do
    read -r label files <<< "$pair"
    file_args=()
    for f in $files; do
        [ -f "${ROOT_DIR}/$f" ] && file_args+=("${ROOT_DIR}/$f")
    done
    [ ${#file_args[@]} -eq 0 ] && continue

    out=$(awk -v label="$label" '
        { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
        /^$/ { next }
        
        {
            sym = ""
            val = ""
            if ($0 ~ /^# CONFIG_[a-zA-Z0-9_]+ is not set$/) {
                sym = $2
                val = "n"
            } else if ($0 !~ /^#/ && index($0, "=") > 0) {
                split($0, arr, "=")
                sym = arr[1]
                val = substr($0, index($0, "=") + 1)
            } else {
                next
            }
            
            if (sym !~ /^CONFIG_/) {
                print "ERROR [" label "] Invalid symbol name without CONFIG_ prefix at " FILENAME ":" FNR ": " sym
                next
            }
            
            if (sym in seen && sym != "CONFIG_EXTRA_FIRMWARE" && sym != "CONFIG_EXTRA_FIRMWARE_DIR") {
                print "ERROR [" label "] Duplicate symbol " sym " defined at " FILENAME ":" FNR " and " seen[sym]
            }
            seen[sym] = FILENAME ":" FNR
            
            if (sym ~ /^CONFIG_NET_VENDOR_/ && val == "y") {
                vendor_locs[sym] = FILENAME ":" FNR
            }
        }
        
        END {
            for (v_sym in vendor_locs) {
                v_name = substr(v_sym, 19)
                has_sub = 0
                for (s in seen) {
                    if (s != v_sym && index(s, v_name) > 0) {
                        has_sub = 1
                        break
                    }
                }
                if (has_sub == 0) {
                    print "WARN [" label "] Vendor toggle " v_sym "=y enabled at " vendor_locs[v_sym] " but no subdrivers found"
                }
            }
        }
    ' "${file_args[@]}")

    if [ -n "$out" ]; then
        # Use sed syntax that works everywhere
        echo "$out" | sed 's/^/  [/' | sed 's/ERROR \[/ERROR\] \[/' | sed 's/WARN \[/WARN\] \[/'
        e_cnt=$(echo "$out" | grep -c "^ERROR" || true)
        w_cnt=$(echo "$out" | grep -c "^WARN" || true)
        ((errors += e_cnt))
        ((warnings += w_cnt))
    fi
done

if [ "$errors" -gt 0 ]; then
    echo -e "\nKernel config validation failed with $errors error(s) and $warnings warning(s)."
    exit 1
fi
echo "Kernel config validation passed cleanly ($warnings warning(s))."
exit 0

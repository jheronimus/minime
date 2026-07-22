#!/usr/bin/env python3
import sys
import re
from pathlib import Path

OPENRC_BUILTINS = {
    "net", "mount-root", "localmount", "clock", "modules", "logger",
    "devfs", "sysfs", "procfs", "hwdrivers", "dbus", "bootmisc", "consolefont"
}

def main():
    init_dir = Path("alpine/aports/minime-overlay/files/etc/init.d")
    if not init_dir.exists():
        print("OpenRC init.d directory not found — skipping.")
        sys.exit(0)

    init_files = [f for f in init_dir.iterdir() if f.is_file() and not f.name.startswith(".")]
    print(f"Checking {len(init_files)} OpenRC init script(s)...")

    defined_services = set(f.name for f in init_files)
    defined_services.update(OPENRC_BUILTINS)

    errors = 0

    for script in init_files:
        try:
            content = script.read_text(encoding="utf-8")
        except Exception as e:
            print(f"  [ERROR] Could not read {script}: {e}")
            errors += 1
            continue

        # Extract depend() block and strip backslash continuations
        depend_match = re.search(r"depend\s*\(\)\s*\{([^}]+)\}", content, re.DOTALL)
        if depend_match:
            dep_body = depend_match.group(1)
            # Join backslash continuations
            dep_body_clean = re.sub(r"\\\s*\n", " ", dep_body)
            for line in dep_body_clean.splitlines():
                line_str = line.strip()
                if not line_str or line_str.startswith("#"):
                    continue

                # Match need, use, before, after directives
                m = re.match(r"^\s*(need|use|before|after)\s+(.+)$", line_str)
                if m:
                    kind = m.group(1)
                    target_str = m.group(2)
                    targets = target_str.split()
                    for t in targets:
                        t_clean = t.strip('"\'\\')
                        if not t_clean or t_clean in ("$*", "$@"):
                            continue
                        if t_clean not in defined_services:
                            print(f"  [ERROR] {script.name}: '{kind}' references unknown service '{t_clean}'")
                            errors += 1

    if errors > 0:
        print(f"\nOpenRC dependency check failed with {errors} error(s).")
        sys.exit(1)
    else:
        print("OpenRC dependency check passed cleanly. All service dependencies resolve.")
        sys.exit(0)

if __name__ == "__main__":
    main()

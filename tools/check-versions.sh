#!/bin/sh
# Check that every file carrying the OS version agrees with the Makefile.
#
# OS_VERSION in the Makefile names the artifacts, but the strings the running
# console reports come from files kept by hand: os-release, /etc/issue and
# sw-versions on both partitions, and sw-description inside the update file.
# Bumping the Makefile and missing one of those is exactly what happened
# between 3.0.0 and 3.1.0 -- a device updated to 3.1.0 would have kept
# reporting 3.0.0 from the recovery INFO screen, which is the screen you read
# while diagnosing a broken update. Run from the repository root; CI runs it
# on every push so the drift is caught in seconds, not on a device.
#
# The list below is the answer to "where does the version live"; when a new
# file gains a version string, add it here.

set -u

fail=0

# Read OS_VERSION the way the release workflow reads print-artifacts: from the
# Makefile, accepting any assignment form and ignoring trailing comments.
version="$(sed -nE 's/^OS_VERSION[[:space:]]*(:|\?)?=[[:space:]]*//p' Makefile \
  | head -n1 | sed 's/[[:space:]#].*$//')"

if [ -z "${version}" ]; then
    echo "ERROR: could not read OS_VERSION from the Makefile" >&2
    exit 1
fi

echo "Makefile OS_VERSION: ${version}"

# need <file> <grep -E pattern>: the file must exist and match.
need() {
    if [ ! -f "$1" ]; then
        echo "ERROR: $1: file is missing" >&2
        fail=1
    elif ! grep -qE "$2" "$1"; then
        echo "ERROR: $1: expected version ${version} (pattern: $2)" >&2
        fail=1
    fi
}

# Escape the dots so 3.1.0 cannot match 3x1x0.
v="$(printf '%s' "${version}" | sed 's/\./\\./g')"

need FunKey/board/funkey/rootfs-overlay/etc/os-release       "^VERSION_ID=\"${v}\"$"
need FunKey/board/funkey/rootfs-overlay/etc/os-release       "^VERSION=\"${v} "
need FunKey/board/funkey/rootfs-overlay/etc/os-release       "^PRETTY_NAME=\".*${v}"
need FunKey/board/funkey/rootfs-overlay/etc/issue            " ${v} "
need FunKey/board/funkey/rootfs-overlay/etc/sw-versions      "^rootfs	${v}$"
need FunKey/board/funkey/sw-description                      "version = \"${v}\";"
need Recovery/board/funkey/rootfs-overlay/etc/os-release     "^VERSION_ID=\"${v}\"$"
need Recovery/board/funkey/rootfs-overlay/etc/os-release     "^VERSION=\"${v} "
need Recovery/board/funkey/rootfs-overlay/etc/os-release     "^PRETTY_NAME=\".*${v}"
need Recovery/board/funkey/rootfs-overlay/etc/issue          " ${v} "
need Recovery/board/funkey/rootfs-overlay/etc/sw-versions    "^Recovery	${v}$"
# The release workflow reads the "## Starling-<version>" section of
# CHANGELOG.md for the release notes; a missing section is a warning there,
# but here it is cheap to insist on.
need CHANGELOG.md                                            "^## Starling-${v}$"

if [ "${fail}" -ne 0 ]; then
    echo "" >&2
    echo "Version strings disagree with the Makefile's OS_VERSION." >&2
    echo "Update the files above (or the Makefile) so they all say the same." >&2
    exit 1
fi

echo "All version strings agree."

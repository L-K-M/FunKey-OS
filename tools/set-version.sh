#!/bin/sh
# Set a new release version everywhere it lives, tag it, and push the tag.
#
#   tools/set-version.sh 3.2.0              bump, verify, commit, tag, push
#   tools/set-version.sh 3.2.0 --no-push    everything except the pushes
#   tools/set-version.sh 3.2.0 --any-branch allow running off master
#
# The version is kept in more places than the Makefile: os-release, /etc/issue
# and sw-versions on both partitions, sw-description inside the update file,
# and the artifact names in the README. Bumping them by hand is how 3.1.0
# shipped devices that still said 3.0.0. This script is the one way to move
# them all at once; tools/check-versions.sh (run here, and by CI on every
# push) is the guard that they stayed together.
#
# What it does, in order:
#   1. refuses to run with unrelated uncommitted changes in the way
#   2. insists CHANGELOG.md has a "## Starling-<version>" section -- that
#      section becomes the GitHub release notes; a stub is inserted and the
#      script stops so the notes are written before anything is tagged
#   3. rewrites the version in the Makefile, both os-release files, both
#      /etc/issue files, both sw-versions files, sw-description, and the
#      README's artifact names and title
#   4. runs tools/check-versions.sh
#   5. commits, tags Starling-<version> (annotated), pushes branch and tag
#
# Pushing the tag does NOT publish a release: release.yml is dispatch-only,
# by design -- run it by hand, with the tag as the ref, after the build has
# been verified on hardware.
#
# Portable sed only (works with BSD sed on macOS as well as GNU).

set -u

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

# ---------------------------------------------------------------- arguments

new=""
push=1
any_branch=0

for arg in "$@"; do
    case "${arg}" in
        --no-push)    push=0 ;;
        --any-branch) any_branch=1 ;;
        -h|--help)    usage ;;
        -*)           die "unknown option: ${arg}" ;;
        *)            [ -n "${new}" ] && usage; new="${arg}" ;;
    esac
done

[ -n "${new}" ] || usage

echo "${new}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "version must be numeric X.Y.Z, got: ${new}"

# Run from the repository root, wherever the script was invoked from.
cd "$(dirname "$0")/.." || die "cannot cd to the repository root"
[ -f Makefile ] || die "no Makefile here -- is this the repository root?"

tag="Starling-${new}"

# The files this script owns. The dirty-tree check allows exactly these to be
# modified (so a stopped run can be resumed) and refuses anything else, so
# the release commit cannot sweep up unrelated work.
managed="Makefile
CHANGELOG.md
README.md
FunKey/board/funkey/sw-description
FunKey/board/funkey/rootfs-overlay/etc/os-release
FunKey/board/funkey/rootfs-overlay/etc/issue
FunKey/board/funkey/rootfs-overlay/etc/sw-versions
Recovery/board/funkey/rootfs-overlay/etc/os-release
Recovery/board/funkey/rootfs-overlay/etc/issue
Recovery/board/funkey/rootfs-overlay/etc/sw-versions"

# ------------------------------------------------------------------- checks

dirty="$(git status --porcelain)" || die "git status failed"
if [ -n "${dirty}" ]; then
    echo "${dirty}" | while IFS= read -r line; do
        f="${line#???}"
        echo "${managed}" | grep -qxF "${f}" \
            || die "uncommitted change outside the version files: ${f} -- commit or stash it first"
    done || exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)" || die "cannot read the current branch"
if [ "${branch}" != "master" ] && [ "${any_branch}" -ne 1 ]; then
    die "on '${branch}', not master -- releases are cut from master (--any-branch to override)"
fi

old="$(sed -nE 's/^OS_VERSION[[:space:]]*(:|\?)?=[[:space:]]*//p' Makefile \
  | head -n1 | sed 's/[[:space:]#].*$//')"
[ -n "${old}" ] || die "could not read OS_VERSION from the Makefile"

git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
    && die "tag ${tag} already exists locally"
if [ "${push}" -eq 1 ]; then
    remote_tag="$(git ls-remote --tags origin "refs/tags/${tag}")" \
        || die "could not check origin for ${tag} -- offline? (--no-push skips this)"
    [ -z "${remote_tag}" ] || die "tag ${tag} already exists on origin"
fi

echo "Version: ${old} -> ${new}  (tag ${tag}, branch ${branch})"

# ---------------------------------------------------------------- changelog

# The release workflow reads the "## Starling-<version>" section of
# CHANGELOG.md as the release notes. Notes are written by a person, so if the
# section is missing, plant a stub and stop -- the tag must not exist before
# the notes do. Re-running after writing them picks up where this left off.
if ! grep -qE "^## ${tag}\$" CHANGELOG.md; then
    awk -v tag="${tag}" '
        !inserted && /^## / {
            print "## " tag
            print ""
            print "_Write the release notes for this version here; this section becomes"
            print "the GitHub release notes when release.yml is dispatched on the tag._"
            print ""
            inserted = 1
        }
        { print }
    ' CHANGELOG.md > CHANGELOG.md.tmp~ && mv CHANGELOG.md.tmp~ CHANGELOG.md \
        || die "could not edit CHANGELOG.md"
    grep -qE "^## ${tag}\$" CHANGELOG.md \
        || die "could not insert a \"## ${tag}\" section into CHANGELOG.md -- add it by hand"
    echo ""
    echo "CHANGELOG.md had no \"## ${tag}\" section; a stub was inserted."
    echo "Write the release notes there, then run this script again."
    exit 1
fi

# -------------------------------------------------------------------- bumps

# sed -i is not portable between GNU and BSD; write a sibling and cat it back
# over the original, which keeps the file's mode (README.md is executable
# here, and a mv would silently drop that).
edit() {
    f="$1"; shift
    [ -f "${f}" ] || die "missing file: ${f}"
    sed -E "$@" "${f}" > "${f}.tmp~" && cat "${f}.tmp~" > "${f}" && rm -f "${f}.tmp~" \
        || die "could not edit ${f}"
}

# The old version with its dots made literal, for use in match patterns.
oldre="$(printf '%s' "${old}" | sed 's/\./\\./g')"

edit Makefile \
    -e "s/^(OS_VERSION[[:space:]]*=[[:space:]]*).*/\1${new}/"

for part in FunKey Recovery; do
    edit "${part}/board/funkey/rootfs-overlay/etc/os-release" \
        -e "s/^(VERSION=\")[0-9.]+ /\1${new} /" \
        -e "s/^(VERSION_ID=\")[0-9.]+(\")/\1${new}\2/" \
        -e "s/^(PRETTY_NAME=\"Starling( Recovery)? )[0-9.]+/\1${new}/"
    edit "${part}/board/funkey/rootfs-overlay/etc/issue" \
        -e "s/(Starling )[0-9]+\.[0-9]+\.[0-9]+/\1${new}/"
    edit "${part}/board/funkey/rootfs-overlay/etc/sw-versions" \
        -e "s/^((rootfs|Recovery)[[:space:]]+)[0-9.]+\$/\1${new}/"
done

edit FunKey/board/funkey/sw-description \
    -e "s/(version = \")[0-9.]+(\";)/\1${new}\2/"

# The README states the artifact names (install table, dd command, update
# step) and titles itself with the version. Only those mechanical spots are
# rewritten; prose that mentions old versions is history and is left alone.
edit README.md \
    -e "s/Starling-${oldre}-RG_Nano/Starling-${new}-RG_Nano/g" \
    -e "s/FunKey-sdk-Starling-${oldre}\.tar\.gz/FunKey-sdk-Starling-${new}.tar.gz/g" \
    -e "s/^# Starling ${oldre}\$/# Starling ${new}/"

# ------------------------------------------------------------------- verify

sh tools/check-versions.sh || die "the bump left the version files inconsistent -- fix before tagging"

# Leftover mentions of the old version outside the history files are not an
# error -- prose like "what changed since X" is legitimate -- but the person
# cutting the release should see them once and decide.
leftovers="$(git grep -n "${oldre}" -- . \
    ':(exclude)CHANGELOG.md' ':(exclude)ANALYSIS.md' \
    ':(exclude)glm.md' ':(exclude)kimi.md' 2>/dev/null || true)"
if [ -n "${leftovers}" ]; then
    echo ""
    echo "Note: ${old} is still mentioned here (fine if it is prose about the past):"
    echo "${leftovers}" | sed 's/^/    /'
fi

# -------------------------------------------------------------- commit, tag

# shellcheck disable=SC2086 -- the managed list is newline-separated paths
git add -- ${managed} || die "git add failed"

if git diff --cached --quiet; then
    echo "No file changes (already at ${new}); proceeding to tag."
else
    git commit -m "Starling ${new}" || die "git commit failed"
fi

git tag -a "${tag}" -m "Starling ${new}" || die "git tag failed"
echo "Tagged $(git rev-parse --short HEAD) as ${tag}."

# --------------------------------------------------------------------- push

if [ "${push}" -eq 1 ]; then
    git push -u origin "${branch}" || die "pushing ${branch} failed"
    git push origin "${tag}"       || die "pushing ${tag} failed"
    echo "Pushed ${branch} and ${tag}."
else
    echo "Not pushed (--no-push). When ready:"
    echo "    git push -u origin ${branch} && git push origin ${tag}"
fi

echo ""
echo "Pushing the tag does not publish anything. To release: verify a build"
echo "on hardware, then dispatch the Release workflow with ${tag} as the ref."

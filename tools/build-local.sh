#!/bin/sh
# Build the working tree -- uncommitted changes and all -- in the same
# container image CI uses.
#
#   tools/build-local.sh                          make all
#   tools/build-local.sh image update             any Makefile target
#   tools/build-local.sh FunKey/retrofe-dirclean image update
#   tools/build-local.sh --log                    show the last build's br.log
#   tools/build-local.sh --shell                  a shell in the build tree
#   tools/build-local.sh --reset                  throw the build state away
#
# Why this exists rather than "docker build && docker run":
#
# docker/Dockerfile clones the repository from GitHub, so a plain docker build
# builds whatever is on master -- not what is in front of you. Local changes,
# committed or not, are simply absent, and the build still succeeds and still
# produces a plausible .fwu. This copies the working tree in instead.
#
# The build runs on a Docker volume, not on a bind mount of the source. A
# buildroot build writes several gigabytes and installs a cross toolchain,
# which means hardlinks, symlinks and files whose names differ only in case.
# A macOS filesystem is case-insensitive by default, and its bind mounts do
# not implement every operation the same way ext4 does; putting the output on
# a Linux volume keeps all of that inside Linux. It is also much faster.
#
# The volume persists between runs, so a second build resumes rather than
# restarting -- which matters when the first one takes hours under emulation.
# --reset is how you deliberately start over.
#
# buildroot is the one directory that is not copied: it is a submodule, and the
# container clones it itself. See the note above check_buildroot.

set -u

IMAGE=starling-build-env
VOLUME=starling-build-state
CONTAINER=starling-build
SRC=/home/funkey/FunKey-OS
# The prebuilt cross toolchain buildroot downloads is an x86_64 binary, so the
# container has to be x86_64 even on an Apple Silicon Mac, where Docker
# emulates one. Without this the build dies early in toolchain-external-custom.
PLATFORM=linux/amd64

die() {
    echo "ERROR: $*" >&2
    exit 1
}

say() {
    echo ""
    echo "=== $*"
}

cd "$(dirname "$0")/.." || die "cannot cd to the repository root"
root="$(pwd)"
[ -f Makefile ] || die "no Makefile here -- is this the repository root?"

# ------------------------------------------------------------------ options

targets=""
mode=build

for arg in "$@"; do
    case "${arg}" in
        --shell) mode=shell ;;
        --reset) mode=reset ;;
        --log)   mode=log ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
            exit 2
            ;;
        -*) die "unknown option: ${arg}" ;;
        *)  targets="${targets} ${arg}" ;;
    esac
done

# "all" (image + update), not CI's "sdk all". The two are independent targets:
# nothing in all -> image/update -> fun depends on sdk. The OS build gets its
# cross compiler by downloading the prebuilt one named in
# BR2_TOOLCHAIN_EXTERNAL_URL; "make sdk" builds a *new* toolchain from source,
# gcc and all, purely to publish as a release artifact for people writing
# software for the console. CI runs it because CI publishes that artifact.
#
# Locally it is an hours-long emulated gcc bootstrap that produces nothing you
# need to flash a card. Ask for it by name if you want it.
[ -n "${targets}" ] || targets=" all"

# ---------------------------------------------------------------- pre-flight

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker info >/dev/null 2>&1 \
    || die "the Docker daemon is not reachable -- is Docker Desktop running?"

if [ "${mode}" = reset ]; then
    docker rm -f "${CONTAINER}" >/dev/null 2>&1
    docker volume rm "${VOLUME}" >/dev/null 2>&1
    echo "Removed the build container and its state. The next build starts over."
    exit 0
fi

# ---------------------------------------------------------- image, container

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    say "Building the ${IMAGE} image (once; several minutes)"
    docker build --platform "${PLATFORM}" -t "${IMAGE}" docker \
        || die "docker build failed"
fi

if ! docker container inspect "${CONTAINER}" >/dev/null 2>&1; then
    say "Creating the ${CONTAINER} container"
    docker run --platform "${PLATFORM}" -d --name "${CONTAINER}" \
        -v "${VOLUME}:${SRC}" "${IMAGE}" sleep infinity >/dev/null \
        || die "could not start the build container"
    # The volume is seeded from the image, which cloned as root.
    docker exec -u root "${CONTAINER}" chown -R funkey:funkey "${SRC}" \
        || die "could not take ownership of the build tree"
elif [ "$(docker container inspect -f '{{.State.Running}}' "${CONTAINER}")" != true ]; then
    docker start "${CONTAINER}" >/dev/null || die "could not start ${CONTAINER}"
fi

# -i because the working-tree copy below pipes a tar stream into this; without
# it docker exec does not attach stdin and the receiving tar reads an empty
# stream ("This does not look like a tar archive"). Harmless for the commands
# that read nothing.
in_container() {
    docker exec -i -u funkey -w "${SRC}" "${CONTAINER}" "$@"
}

# buildroot is a submodule, and it is deliberately not copied in. The Makefile
# fetches it itself:
#
#     buildroot/.git:
#             git submodule init && git submodule update
#
# That rule runs whenever buildroot/.git is missing, and it is always missing
# in the container: .git is not copied, because the container needs its own
# clone for exactly this rule to work. Sending buildroot's files in therefore
# left git cloning into a directory that already had a buildroot in it, which
# it refuses to do -- "already exists and is not an empty directory" -- and the
# build stopped before it started. So the container clones buildroot, as CI
# does, and half a gigabyte of untouched upstream sources stays out of every
# copy.
#
# The price is that a buildroot differing from the container's is not the one
# that gets built. Building something other than what is in front of you is the
# whole thing this script exists to prevent, so say so rather than let it pass.
check_buildroot() {
    want="$(git rev-parse -q --verify HEAD:buildroot 2>/dev/null || true)"
    have="$(in_container git rev-parse -q --verify HEAD:buildroot 2>/dev/null || true)"

    if [ -n "${want}" ] && [ -n "${have}" ] && [ "${want}" != "${have}" ]; then
        echo ""
        echo "NOTE: the container pins a different buildroot than this tree does."
        echo "        here:      ${want}"
        echo "        container: ${have}"
        echo "      The build uses the container's. To refresh it:"
        echo "        docker rmi ${IMAGE} && tools/build-local.sh --reset"
    fi

    if [ -n "$(git status --porcelain -- buildroot 2>/dev/null)" ]; then
        echo ""
        echo "NOTE: buildroot/ has local changes here. They are not copied in --"
        echo "      the container builds the submodule commit it cloned."
    fi
}

show_log() {
    if ! in_container test -f br.log; then
        echo "No br.log in the build tree yet."
        return
    fi

    # A buildroot log ends in a cascade: every enclosing make reports that its
    # child failed, so the last lines name the recursion, not the cause. The
    # cause sits just above the *first* "make[n]: ***", which is what this
    # prints -- the tail is shown too, but second, and only as orientation.
    say "First failure in br.log, with the 30 lines before it"
    in_container sh -c \
        "grep -n -m1 -B30 'make\\[[0-9]*\\]: \\*\\*\\*' br.log || tail -n 40 br.log"

    say "End of br.log"
    in_container tail -n 15 br.log

    if docker cp "${CONTAINER}:${SRC}/br.log" "${root}/br.log" >/dev/null 2>&1; then
        echo ""
        echo "Full log: ${root}/br.log"
    fi
}

case "${mode}" in
    log)   show_log; exit 0 ;;
    shell) exec docker exec -it -u funkey -w "${SRC}" "${CONTAINER}" /bin/bash ;;
esac

# ------------------------------------------------------------------ the copy

# What the copy leaves behind matters as much as what it sends. The container's
# tree starts as a clone of master, so a file this tree renamed or deleted is
# still sitting there -- and buildroot applies every .patch in a package
# directory, in name order. A patch renamed here and left there is applied
# twice, under two numbers. So the source is cleared out first and this tree is
# laid down whole; only the build's own output survives, which is what makes a
# second run resume rather than restart.
#
# Both sides skip the same paths, named here once. No parentheses: the sending
# find gets this by word splitting, the receiving one gets it inside sh -c, and
# a form that needs no quoting is a form that cannot be quoted wrong.
#
#   .git       the container has its own, and the submodule rule needs it
#   buildroot  cloned in the container -- see check_buildroot above
#   br.log     the container writes its own; it is cleared just before the build
#   the rest   build output, which lives in the volume
KEEP="-path ./.git -prune \
-o -path ./buildroot -prune \
-o -path ./FunKey/output -prune \
-o -path ./Recovery/output -prune \
-o -path ./SDK/output -prune \
-o -path ./download -prune \
-o -path ./images -prune \
-o -path ./br.log -prune"

say "Copying the working tree into the container"

# shellcheck disable=SC2086 -- KEEP is a find expression, deliberately split
in_container sh -c "find . ${KEEP} -o ! -type d -print0 | xargs -0 -r rm -f --" \
    || die "clearing the previous copy out of the container failed"

list="$(mktemp)" || die "cannot create a temporary file"

# Directories are left out of the list deliberately. tar creates the ones it
# needs as it extracts, and a list of files alone leaves it nothing to recurse
# into -- so the pruning above holds without --no-recursion, which GNU tar and
# the bsdtar on macOS do not spell the same way. Names go one per line, which
# is how both read -T, and several hundred of these have spaces in them.
# shellcheck disable=SC2086 -- KEEP is a find expression, deliberately split
find . ${KEEP} -o ! -type d -print > "${list}" \
    || { rm -f "${list}"; die "listing the working tree failed"; }

tar -cf - -T "${list}" | in_container tar -xf - -C "${SRC}"
copied=$?
rm -f "${list}"
[ "${copied}" -eq 0 ] || die "copying the working tree in failed"

# ----------------------------------------------------------------- the build

check_buildroot

# So that a build dying before buildroot starts cannot be read through the
# previous run's log.
in_container rm -f br.log

say "make${targets}"
echo "(the first build clones buildroot and takes hours under emulation;"
echo " later ones resume)"
echo ""

# shellcheck disable=SC2086 -- targets is a deliberately split list
if in_container make ${targets}; then
    status=0
else
    status=$?
fi

if [ "${status}" -ne 0 ]; then
    # The Makefile runs buildroot through brmake, which prints only the ">>>"
    # progress lines and sends everything else to br.log. On a failure the
    # terminal therefore shows the last package that started and nothing about
    # what went wrong, so print the log rather than leaving it to be found.
    show_log
    say "Build failed (exit ${status})"
    echo "Fix, then re-run -- the build resumes rather than starting over."
    echo "For a shell in the tree as it stands: tools/build-local.sh --shell"
    exit "${status}"
fi

# --------------------------------------------------------------- the results

say "Copying images/ out"
rm -rf "${root}/images.new"
if docker cp "${CONTAINER}:${SRC}/images" "${root}/images.new" >/dev/null 2>&1; then
    rm -rf "${root}/images"
    mv "${root}/images.new" "${root}/images"
    ls -lh "${root}/images" | sed 's/^/  /'
else
    rm -rf "${root}/images.new"
    echo "  no images/ in the container -- did the target build one?"
fi

say "Done"

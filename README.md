[![FunKey-OS Build](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml?query=branch%3Amaster)

# FunKey OS — Favorites fork

FunKey OS for the [FunKey S](https://www.funkey-project.com/) and compatible
handhelds, with a **Favorites** feature added.

Forked from [DrUm78/FunKey-OS](https://github.com/DrUm78/FunKey-OS), itself a
fork of the original
[FunKey-Project/FunKey-OS](https://github.com/FunKey-Project/FunKey-OS).

> ## ⚠️ Do not install this yet
>
> **This has never been verified on hardware.** The 3.0.0 release was published
> on the strength of a green CI build, and installing that `.fwu` left an
> RG Nano showing a grey screen at power-on. The release has been withdrawn.
>
> The cause is not yet known. Until it is, build from source only if you are
> prepared to recover the device, and use
> [DrUm78/FunKey-OS](https://github.com/DrUm78/FunKey-OS/releases) for anything
> you actually want to play on.
>
> Note also that this tree contains no RG Nano, Q36 Mini or GBA Mini support of
> its own: it builds one image, and `etc/hwrevision` is hardcoded to
> `FunKey_S Rev.F`.
>
> If you have already installed it, see [Recovery](#recovery).

## What is different from upstream

- **[Favorites](#favorites)** — mark a game with **Y** and reach every game you
  have marked, across all systems, from one entry in the main menu.
- **Working build workflow** — the CI pinned a runner image GitHub has retired,
  so it could never run. It builds on `ubuntu-22.04` and publishes the images.
- **Working Docker build** — the container was based on Debian buster, which is
  past end of life and no longer served, so `apt-get update` failed; it also
  cloned upstream, so it built without Favorites even when run from here.

For what FunKey OS is and how it works, see
**[upstream's README](https://github.com/DrUm78/FunKey-OS/blob/master/README.md)**.
Its build instructions clone upstream, so use [Build from source](#build-from-source)
below instead, or the result will not have Favorites.

## Install

There is no published release — it was withdrawn, see the warning above. Get
`FunKey-sdcard-DrUm78.img` by [building from source](#build-from-source).

Write it to an SD card with
[Balena Etcher](https://www.balena.io/etcher/), or:

```bash
sudo dd if=FunKey-sdcard-DrUm78.img of=/dev/sdX bs=4M conv=fsync status=progress
```

> **Warning:** make sure `/dev/sdX` really is the SD card and not one of your
> own disks. Writing the image erases everything already on that card, unlike
> the update below.

Insert the card into the console and power it on.

## Update

Updating replaces the OS only — games, saves and favorites are kept.

1. Get `FunKey-rootfs-DrUm78.fwu` by [building from source](#build-from-source).
   Read the warning above first — these images are unverified on hardware.
2. Connect the console to your computer over USB.
3. In the game launcher press **ON/OFF**, select **MOUNT USB**, press **A** twice.
4. Copy the `.fwu` onto the drive that appears.
5. Eject the drive on your computer, then press **A** twice on the console.

The console applies the update and returns to the launcher.

## Recovery

If the console shows a grey screen at power-on and never reaches the launcher,
the Recovery partition is still intact: an update writes only `/dev/mmcblk0p2`,
and Recovery lives on `p1`.

**Hold FN + START while powering on.** `S60recovery` reads the key matrix at
boot and opens the recovery menu instead of booting the OS.

1. Select the **USB** entry and press **A** to mount. The console appears as a
   drive on your computer.
2. Delete the `.fwu` you copied, and put a known-good one in its place —
   [DrUm78's releases](https://github.com/DrUm78/FunKey-OS/releases), or
   whatever build the console shipped with.
3. Eject the drive on your computer, then press **A** again to unmount — that
   is what runs `swupdate` on any `/mnt/FunKey-*.fwu`. Eject first: flashing
   starts the moment you unmount, so a copy the host has not flushed would be
   flashed truncated.
4. Select **EXIT RECOVERY**.

The **INFO** entry is worth checking first: it mounts `p2` read-only and prints
the rootfs version, which tells you whether the filesystem is intact at all.
**NETWORK: ENABLED** plus SSH over USB gets you a shell for reading logs.

## Favorites

**Favorites** is the first entry in the main menu. It gathers the games you have
marked from every system and launches each with its own emulator. It is empty
until you mark something.

| Button | Action |
| --- | --- |
| **Y** | Mark the highlighted game as a favorite, or unmark it |
| **X** | Unmark the highlighted game |
| **START** | Switch between favorites and all games for the current system |
| **FN + L** / **FN + R** | Previous / next playlist |

Each system keeps its own list, and the menu entry is assembled from those, so
nothing can fall out of sync. The lists live on the writable partition at
`/mnt/FunKey/.retrofe/collections/<System>/playlists/favorites.txt` and survive
a firmware update.

All 13 bundled themes ship Favorites artwork. A theme you add yourself needs a
`collections/Favorites/system_artwork/` directory, or the entry falls back to a
plain text label — `tools/gen-favorites-artwork.py` generates one.

## Build from source

Both paths below produce the same files in `images/`, and both compile the
whole OS from source: budget **1.5–3 hours** and **~12 GB** of free disk.

### With Docker

Only Docker is needed — the container brings its own toolchain and clones this
fork itself, so there is nothing to check out first.

```bash
curl -O https://raw.githubusercontent.com/L-K-M/FunKey-OS/master/docker/Dockerfile
docker build --platform linux/amd64 -t funkey-os .
docker run --platform linux/amd64 --name funkey-os funkey-os
docker cp funkey-os:/home/funkey/FunKey-OS/images ./images
```

> **`--platform linux/amd64` is not optional on Apple Silicon.** The
> cross-toolchain the build downloads is an x86_64 binary, so it can only run in
> an x86_64 container. The flag does nothing on an Intel or AMD machine, and
> makes Docker Desktop emulate one on an ARM Mac — slower, but it completes.
> Without it the container is ARM, and the build fails minutes in at
> `>>> toolchain-external-custom … Configuring`.

To build a different fork or branch, pass
`--build-arg FUNKEY_OS_REPO=<url>` and `--build-arg FUNKEY_OS_REF=<branch>`
to `docker build`.

### Natively

Tested on Ubuntu 22.04 and Debian 12; this is the package set the CI uses.
Ubuntu 24.04 and Debian 13 dropped `python3-distutils`, which buildroot still
wants.

```bash
sudo apt install make binutils build-essential gcc g++ patch bzip2 perl cpio \
  unzip rsync file bc wget xxd libncurses5-dev cvs git mercurial liblscp-dev \
  subversion python3 python3-dev python3-distutils python3-setuptools \
  ca-certificates openssh-client expect locales sudo procps

git clone https://github.com/L-K-M/FunKey-OS.git
cd FunKey-OS
make sdk all
```

`make sdk` builds the cross-toolchain and `make all` the OS. The files that end
up in `images/` are the same ones a release ships, so [Install](#install) and
[Update](#update) apply from there on.

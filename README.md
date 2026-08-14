[![FunKey-OS Build](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml?query=branch%3Amaster)

# FunKey OS — Favorites fork

FunKey OS for the [FunKey S](https://www.funkey-project.com/) and compatible
handhelds, with a **Favorites** feature added.

Forked from [DrUm78/FunKey-OS](https://github.com/DrUm78/FunKey-OS), itself a
fork of the original
[FunKey-Project/FunKey-OS](https://github.com/FunKey-Project/FunKey-OS).

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

Download `FunKey-sdcard-DrUm78.img` from the
[latest release](https://github.com/L-K-M/FunKey-OS/releases/latest).

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

1. Download `FunKey-rootfs-DrUm78.fwu` from the
   [latest release](https://github.com/L-K-M/FunKey-OS/releases/latest).
2. Connect the console to your computer over USB.
3. In the game launcher press **ON/OFF**, select **MOUNT USB**, press **A** twice.
4. Copy the `.fwu` onto the drive that appears.
5. Eject the drive on your computer, then press **A** twice on the console.

The console applies the update and returns to the launcher.

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
docker build -t funkey-os .
docker run --name funkey-os funkey-os
docker cp funkey-os:/home/funkey/FunKey-OS/images ./images
```

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

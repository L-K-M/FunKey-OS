[![FunKey-OS Build](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml?query=branch%3Amaster)

# FunKey OS — Favorites fork (Anbernic RG Nano)

FunKey OS for the **Anbernic RG Nano**, with a **Favorites** feature added.

Forked from the `rg_nano` branch of
[DrUm78/FunKey-OS](https://github.com/DrUm78/FunKey-OS/tree/rg_nano), itself a
fork of the original
[FunKey-Project/FunKey-OS](https://github.com/FunKey-Project/FunKey-OS).

> ## ⚠️ Not yet verified on hardware
>
> **This build has never been booted on a device.** Do not install it on a
> console you care about; use
> [DrUm78's releases](https://github.com/DrUm78/FunKey-OS/releases) for that.
>
> If you have installed something from here and the console shows a grey screen
> at power-on, see [Recovery](#recovery).

## Which device this builds for

Upstream keeps one branch per console, and **the branches are not
interchangeable** — they use different kernels:

| Upstream branch | Console | Kernel |
| --- | --- | --- |
| `master` | FunKey S | `v1.0.3-funkey-s` |
| **`rg_nano`** | **Anbernic RG Nano** | **`v1.0-rg-nano`** |
| `q36_mini` | Q36 Mini | |
| `gba_mini` | GBA Mini | |

They also differ in `linux.config` for both partitions, the buildroot submodule
commit, and RG Nano-specific audio, GPIO and sysctl init.

This fork tracks **`rg_nano`**. Flashing a build from the wrong branch gives a
grey screen at power-on with no launcher — on Recovery as well as the main OS,
since both partitions carry their own copy of the kernel. The withdrawn 3.0.0
release of this fork was built from `master`, which is why it did exactly that.
Artifact names carry the device (`…_RG_Nano`) so a file cannot be mistaken for
another console's.

## What is different from upstream

- **[Favorites](#favorites)** — mark a game with **Y** and reach every game you
  have marked, across all systems, from one entry in the main menu.
- **Working build workflow** — the CI pinned a runner image GitHub has retired,
  so it could never run. It builds on `ubuntu-22.04` and publishes the images.
- **Working Docker build** — the container was based on Debian buster, which is
  past end of life and no longer served, so `apt-get update` failed; it also
  cloned upstream, so it built without Favorites even when run from here.

For what FunKey OS is and how it works, see
**[upstream's README](https://github.com/DrUm78/FunKey-OS/blob/rg_nano/README.md)**.
Its build instructions clone upstream, so use [Build from source](#build-from-source)
below instead, or the result will not have Favorites.

## Install

There is no published release — it was withdrawn, see the warning above. Get
`FunKey-sdcard-Favorites_RG_Nano.img` by [building from source](#build-from-source).

Write it to an SD card with
[Balena Etcher](https://www.balena.io/etcher/), or:

```bash
sudo dd if=FunKey-sdcard-Favorites_RG_Nano.img of=/dev/sdX bs=4M conv=fsync status=progress
```

> **Warning:** make sure `/dev/sdX` really is the SD card and not one of your
> own disks. Writing the image erases everything already on that card, unlike
> the update below.

Insert the card into the console and power it on.

## Update

Updating replaces the OS only — games, saves and favorites are kept.

1. Get `FunKey-rootfs-Favorites_RG_Nano.fwu` by [building from source](#build-from-source).
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

**Hold FN + START while powering on.** u-boot reads the key matrix over I2C and
boots `p1` instead of the flagged partition. Be holding the buttons *before* you
press power: `bootdelay=0` and `delay=1`, so it samples once, immediately. The
combination is named for FunKey S hardware and may not correspond to any pair of
buttons on another console.

**If that does not work**, set the boot flag from a computer instead — this is
the same mechanism, and it is what `normal_mode` does in reverse
(`sfdisk -A /dev/mmcblk0 2`). u-boot boots whichever partition is flagged, so
flagging `p1` selects Recovery with no buttons involved:

```bash
diskutil unmountDisk /dev/diskN     # macOS; lsblk to find it on Linux
sudo fdisk -e /dev/diskN
  flag 1
  write
  quit
```

**EXIT RECOVERY** flips it back to `p2`, so this is reversible from the device.

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

[![Build](https://github.com/L-K-M/FunKey-OS-Starling/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/L-K-M/FunKey-OS-Starling/actions/workflows/build.yml?query=branch%3Amaster)

# Starling 3.1.0

**FunKey OS for the [Anbernic RG Nano](https://anbernic.com/), with a Favorites
feature added.**

Mark any game with **Y** and it appears under **Favorites**, the first entry in
the main menu — one list gathering games from every system, each still launching
with its own emulator.

Everything else is stock FunKey OS. Starling is a fork of the `rg_nano` branch
of [DrUm78/FunKey-OS](https://github.com/DrUm78/FunKey-OS/tree/rg_nano), which
is itself a fork of
[FunKey-Project/FunKey-OS](https://github.com/FunKey-Project/FunKey-OS). For
what FunKey OS *is*, read
[upstream's README](https://github.com/DrUm78/FunKey-OS/blob/rg_nano/README.md);
this one covers only what Starling adds and how to install it.

> ### ⚠️ Early days
>
> Starling 3.0.0 booted and ran on an Anbernic RG Nano — but on exactly one, and
> not for long. **3.1.0 has not been on hardware at all yet**: everything it
> changes was verified by compiling it, which cannot tell you what the screen
> does. Keep a card with a known-good build on it, and read
> [Recovery](#recovery) before you flash something rather than after.

## This build is for the RG Nano and no other console

Upstream keeps **one branch per console**, and they are not interchangeable —
each uses a different kernel:

| Upstream branch | Console | Kernel |
| --- | --- | --- |
| **`rg_nano`** | **Anbernic RG Nano** ← Starling | **`v1.0-rg-nano`** |
| `master` | FunKey S | `v1.0.3-funkey-s` |
| `q36_mini` | Q36 Mini | |
| `gba_mini` | GBA Mini | |

They also differ in kernel config for both partitions, the buildroot submodule,
and RG Nano-specific audio, GPIO and sysctl init.

**Flashing a build meant for a different console gives a grey screen at power-on
and nothing else** — on Recovery as well as the main OS, because both partitions
carry their own copy of the kernel. Nothing in a checkout tells you which branch
you are on, which is exactly how it happens.

Starling's filenames therefore carry the console, the version and the fork:

| File | What it is |
| --- | --- |
| `FunKey-sdcard-Starling-3.1.0-RG_Nano.img` | Full SD card image — installs Starling, erasing the card |
| `FunKey-rootfs-Starling-3.1.0-RG_Nano.fwu` | Firmware update — replaces the OS in place, keeping games and saves |
| `FunKey-sdk-Starling-3.1.0.tar.gz` | Cross-toolchain, only needed to build software *for* the console |

The `FunKey-` prefix is not decoration and must not be removed: the console
finds an update by globbing `/mnt/FunKey-*.fwu`, and that glob runs from the
firmware **already installed**, in `S60recovery`, the recovery menu and
`update_partition`. A name that stops matching is invisible to the device it was
built for. The SDK carries no console because `SDK/` is identical across the
branches — the toolchain genuinely is shared.

## Favorites

**Favorites** is the first entry in the main menu. It is empty until you mark
something.

| Button | Action |
| --- | --- |
| **Y** | Mark the highlighted game as a favorite, or unmark it |
| **X** | Unmark the highlighted game |
| **START** | Switch between favorites and all games, within one system |
| **FN + L** / **FN + R** | Previous / next playlist |

Pressing **Y** does two visible things: a favorited game keeps a `*` in front of
its name, so you can see what is marked without opening Favorites, and a short
**Added to favorites** / **Removed from favorites** notice appears over the
screen. That notice is the same overlay volume, brightness and screenshots use,
so it shows above every theme, including ones you add yourself.

Inside Favorites the title bar names each game's own system rather than
"Favorites", which is also which emulator is about to run.

Each system keeps its own list and the Favorites menu is assembled from those,
so there is no second list to fall out of sync. Marking a game from inside
Favorites writes back to the system it actually belongs to. The lists live on
the writable partition:

```
/mnt/FunKey/.retrofe/collections/<System>/playlists/favorites.txt
```

so they survive a firmware update. Games launch with their own system's
emulator, whether started from Favorites or from the system's own menu.

All 13 bundled themes ship Favorites artwork. A theme you add yourself needs a
`collections/Favorites/system_artwork/` directory or the entry falls back to a
plain text label; `tools/gen-favorites-artwork.py` generates one.

## Install

Write the `.img` to an SD card — this erases everything on the card:

```bash
sudo dd if=FunKey-sdcard-Starling-3.1.0-RG_Nano.img of=/dev/sdX bs=4M conv=fsync status=progress
```

> **Check `/dev/sdX` twice.** Naming one of your own disks here destroys it.

[Balena Etcher](https://www.balena.io/etcher/) does the same thing with more
guard rails. Then insert the card and power on; the first boot resizes the
filesystem and creates the swap and share partitions.

## Button map

Everything the launcher listens for, not just the favorites keys. FN is the
small round button; **FN + X** means hold FN and tap X.

| Button | Action |
| --- | --- |
| **D-pad** | Move through the menus |
| **A** | Open the highlighted system or launch the highlighted game |
| **B** | Back |
| **Y** | Mark the highlighted game as a favorite, or unmark it |
| **X** | Unmark the highlighted game (same as Y on a game that is already marked) |
| **START** | Switch between favorites and all games, within one system |
| **L** / **R** | Jump to the previous / next letter of the alphabet |
| **FN + L** / **FN + R** | Previous / next playlist |
| **FN** (alone) | Launch a random game from the list you are looking at — inside Favorites this means a random favorite |
| **MENU** | Quick menu: volume, brightness, USB sharing, theme, launcher, power down |
| **FN + A** / **FN + Y** | Volume up / down |
| **FN + X** / **FN + B** | Brightness up / down |
| **FN + L + R** | System statistics overlay |
| **FN + UP** | Screenshot |

## Update

Replaces the OS only — games, saves and favorites are kept.

1. Connect the console to your computer over USB.
2. In the launcher press **ON/OFF**, select **MOUNT USB**, press **A** twice.
3. Copy `FunKey-rootfs-Starling-3.1.0-RG_Nano.fwu` onto the drive that appears.
4. **Eject the drive on your computer**, then press **A** twice on the console.

Ejecting first matters: unmounting is what starts the flash, so a copy your
computer has not finished writing would be flashed truncated.

## Recovery

If the console shows a grey screen at power-on and never reaches the launcher,
Recovery is almost certainly intact — an update writes only `/dev/mmcblk0p2`,
and Recovery lives on `p1`.

**Hold FN + START while powering on.** u-boot reads the key matrix over I2C and
boots `p1` instead of the flagged partition. Hold the buttons *before* pressing
power: with `bootdelay=0` and `delay=1` it samples once, immediately.

**If that does not work** — the combination is named for FunKey S hardware and
may not match any pair of buttons on your console — set the boot flag from a
computer instead. u-boot boots whichever partition is flagged, so this selects
Recovery with no buttons at all, and it is exactly what `normal_mode` does in
reverse (`sfdisk -A /dev/mmcblk0 2`):

Find the card with `diskutil list` on macOS, or `lsblk` on Linux, then:

```bash
diskutil unmountDisk /dev/diskN
sudo fdisk -e /dev/diskN
  flag 1
  write
  quit
```

Either way you land on the recovery menu:

1. Select **USB** and press **A** to mount. The console appears as a drive.
2. Replace the `.fwu` with a known-good one — a Starling release, or
   [DrUm78's](https://github.com/DrUm78/FunKey-OS/releases).
3. Eject the drive on your computer, then press **A** again to unmount. That is
   what runs `swupdate`.
4. **EXIT RECOVERY**, which runs `normal_mode` and flags `p2` again — undoing
   the boot-flag change above.

**INFO** is worth opening first: it mounts `p2` read-only and prints the rootfs
version, which tells you whether the filesystem survived at all.

> If the console is unresponsive even from a card you know is good, it can latch
> into a state a power cycle will not clear. Opening it and briefly
> disconnecting the battery resets it.

### Getting logs out

`/usr/games/log.txt` is a symlink to `/tmp/retrofe.log`, and `/tmp` is tmpfs, so
RetroFE's log never survives a power cycle. To capture one, mount `p2`
read-write from a Recovery shell and repoint it at the share partition:

```sh
ln -sf /mnt/retrofe.log /usr/games/log.txt
```

Also redirect the frontend, since `/root/.profile` ends with
`frontend init >/dev/null 2>&1 &` and discards anything printed before that log
is even open. Both files are then readable from the FAT share partition on any
computer.

## Build from source

Both routes produce the same files in `images/` and compile the whole OS:
budget **1.5–3 hours** and **~12 GB** of free disk.

### With Docker

Only Docker is needed — the container brings its own toolchain and clones this
repository itself.

```bash
curl -O https://raw.githubusercontent.com/L-K-M/FunKey-OS-Starling/master/docker/Dockerfile
docker build --platform linux/amd64 -t starling .
docker run --platform linux/amd64 --name starling starling
docker cp starling:/home/funkey/FunKey-OS/images ./images
```

> **`--platform linux/amd64` is not optional on Apple Silicon.** The
> cross-toolchain the build downloads is an x86_64 binary and can only run in an
> x86_64 container. The flag is a no-op on Intel and AMD machines and makes
> Docker Desktop emulate one on an ARM Mac — slower, but it finishes. Without it
> the build dies a few minutes in at `>>> toolchain-external-custom … Configuring`.

Pass `--build-arg FUNKEY_OS_REPO=<url>` and `--build-arg FUNKEY_OS_REF=<branch>`
to build something else; the default is this repository's `master`.

### Natively

Tested on Ubuntu 22.04 and Debian 12 — the package set CI uses. Ubuntu 24.04 and
Debian 13 dropped `python3-distutils`, which buildroot still wants.

```bash
sudo apt install make binutils build-essential gcc g++ patch bzip2 perl cpio \
  unzip rsync file bc wget xxd libncurses5-dev cvs git mercurial liblscp-dev \
  subversion python3 python3-dev python3-distutils python3-setuptools \
  ca-certificates openssh-client expect locales sudo procps

git clone https://github.com/L-K-M/FunKey-OS-Starling.git
cd FunKey-OS-Starling
make sdk all
```

`make sdk` builds the cross-toolchain and `make all` the OS. `make -s
print-artifacts` prints the three filenames a release publishes; the Makefile is
the only place they are defined.

## What Starling changes

Beyond Favorites, all of it fixes things that were broken in the fork it started
from:

- **The build workflow ran on a runner image GitHub retired**, so it could never
  complete — every run sat queued forever. It builds on `ubuntu-22.04`.
- **The Docker build was based on Debian buster**, past end of life and no
  longer served, so `apt-get update` failed outright. It also cloned upstream
  rather than the fork, so it produced an image without Favorites even when run
  from here.
- **A separate workflow validates the container** in about 45 seconds, rather
  than a two-hour OS build that never reads `docker/` at all.
- **Releases are published by hand** (`workflow_dispatch`), never by pushing a
  tag. A tag push is how a build for the wrong console got published once
  already.

## Branches

| Branch | Console | |
| --- | --- | --- |
| `master` | Anbernic RG Nano | Starling — tracks upstream `rg_nano` |
| `funkey-s` | FunKey S | where Favorites was first written; tracks upstream `master`, not maintained |

Favorites itself is device-independent: it touches RetroFE, collections and
theme artwork, none of which the console branches modify. Porting it to
`q36_mini` or `gba_mini` would be the same operation.

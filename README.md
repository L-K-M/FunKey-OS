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

Everything else is upstream's, including how FunKey OS works and how to build
it from source: see
**[upstream's README](https://github.com/DrUm78/FunKey-OS/blob/master/README.md)**.
Substitute this repository's URL wherever those instructions clone or fetch
from upstream — including the Dockerfile they download — or the result will not
have Favorites.

## Install

Open the [latest build](https://github.com/L-K-M/FunKey-OS/actions/workflows/build.yml?query=branch%3Amaster+is%3Asuccess),
download the `funkey-os-images` artifact from the run page, and unzip it.
Downloading it needs a GitHub account, and artifacts are kept 90 days.

Write `images/FunKey-sdcard-DrUm78.img` to an SD card with
[Balena Etcher](https://www.balena.io/etcher/), or:

```bash
sudo dd if=images/FunKey-sdcard-DrUm78.img of=/dev/sdX bs=4M conv=fsync status=progress
```

> **Warning:** make sure `/dev/sdX` really is the SD card and not one of your
> own disks. Writing the image erases everything already on that card, unlike
> the update below.

Insert the card into the console and power it on.

## Update

Updating replaces the OS only — games, saves and favorites are kept.

1. Connect the console to your computer over USB.
2. In the game launcher press **ON/OFF**, select **MOUNT USB**, press **A** twice.
3. Copy `images/FunKey-rootfs-DrUm78.fwu` onto the drive that appears.
4. Eject the drive on your computer, then press **A** twice on the console.

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

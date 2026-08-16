# Changelog

Release notes read the section matching their tag out of this file, so the
headings are `## Starling-X.Y.Z` — the tag name, exactly.

## Starling-3.1.1

**3.1.0 was tagged but never published, so this is the first release since
3.0.0 — its files carry all of the Favorites work listed under 3.1.0 below, as
well as the fixes here.**

Everything in this release came out of reviewing 3.1.0 rather than running it.

- **The console reports the version it is actually running.** 3.1.0 moved
  `OS_VERSION` and the artifact names but left seven files behind at 3.0.0:
  `os-release`, `/etc/issue` and `sw-versions` on both partitions, and
  `sw-description` inside the update file. A console updated to 3.1.0 would have
  gone on reporting 3.0.0 from the recovery INFO screen — the screen you read
  while working out whether an update landed.
- **The recovery menu shows its corrupted-update notice.** It passed five
  arguments to a helper whose `set` form takes three, so the helper printed its
  usage instead and the one message explaining why the `.fwu` had just been
  deleted never reached the screen before the reboot. (Predates the fork.)
- **A failed favorites save no longer leaves its temp file behind** on the share
  partition, where it was visible to anyone browsing the card over USB. The
  saved list was never at risk; this is debris.
- **New Favorites background** for the default theme.

Nothing above changes what Favorites does — for that, read the 3.1.0 section.

Also, not visible on the console: the version strings are now checked against
the Makefile by CI, so they cannot drift apart again; `tools/set-version.sh`
moves all of them at once and cuts the tag; and a full OS build is no longer
started for changes that cannot affect it.

**Still not booted on hardware.** The tree builds end to end in CI — two hours,
green, including the re-enabled gmu music player — but a build completing is not
the same as a console starting, and the most visible change in 3.1.0 is one only
a device can show. Keep a card with a known-good build on it.

## Starling-3.1.0

Favorites was written and merged before any of it had run on a console. This
release is what came back from actually looking at it: the acknowledgement was
unreadable, the toggle was slow, and the menu said the wrong thing about which
system a game belonged to.

**Not yet booted on hardware.** Everything below was verified by compiling it,
which cannot tell you what the screen does.

### Favorites

- Pressing **Y** now shows its confirmation through the OS notification overlay
  — the one volume, brightness and screenshots use — instead of a line of text
  in the theme. The theme's `statusText` sat at `y=224` while the shipped themes
  centre the game title on 223 or 220, and RetroFE's text draws over what is
  already there without clearing it, so the confirmation and the game title
  arrived on top of each other.
- Toggling a favorite no longer rebuilds every visible slot of the menu. That
  meant a run of file probes and a PNG decode off the SD card for each one, to
  answer a change that touched a single game's title. Only a toggle that changes
  which games the list holds — unfavoriting while looking at Favorites — still
  re-lays the menu out.
- Inside **Favorites**, the title bar names each game's own system rather than
  "Favorites", which is also which emulator is about to run it.
- An empty **Favorites** says how to fill it instead of showing a blank page.
- Unfavoriting a game while looking at Favorites removes it from view, rather
  than leaving it listed until the menu is next rebuilt.
- **Y** and **X** act on games only. On a system in the main menu they used to
  write a playlist of system names that nothing ever displayed, and show a
  confirmation for it.
- Status messages fade in and out rather than appearing and vanishing between
  frames.
- Favorites are saved by writing beside the file and renaming over it, so losing
  power mid-save leaves the previous list intact rather than a truncated one.
- Sorting no longer lowercases every title on every comparison, and playlist
  membership is a set lookup rather than a linear scan.
- Fixed a leak of one collection shell per system per visit to Favorites.

### Elsewhere

- The **gmu** music player is back. It had been disabled because it built its
  own copies of FLAC and WavPack against a hand-installed SDK path that does not
  exist here, silently fell back to the host compiler, and produced x86_64
  libraries that could not link into an ARM binary. It now builds against
  buildroot's own libraries.
- The layout fallback pointed at a theme that is not shipped, so a missing or
  broken theme fell back to nothing.
- A pending firmware update is now detected with any number of `.fwu` files on
  the partition, not just exactly one.
- Unused files and dead configuration dropped from the image.
- CI checks the RetroFE patch series against the pinned upstream tag in under a
  minute, rather than only at the tail of a two-hour OS build.

## Starling-3.0.0

First Starling release, and the first built for the right console.

- Favorites: mark a game with **Y** and it appears under **Favorites**, the
  first entry in the main menu — one list gathering games from every system,
  each still launching with its own emulator.
- Built from upstream's `rg_nano` branch. The version before it was built from
  `master`, which is the FunKey S line: flashing it left an RG Nano at a grey
  screen, on Recovery as well as the main OS, because both partitions carry
  their own copy of the kernel.
- Artifact names carry the fork, the version and the console, so a build for
  one console cannot be mistaken for another.
- Releases are published by hand rather than by pushing a tag — a tag push is
  how the wrong-console build got published in the first place.
- Repaired the build workflow, which ran on a runner image GitHub had retired
  and so sat queued forever, and the Docker build, which was based on an
  end-of-life Debian whose `apt-get update` failed outright.

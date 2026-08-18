# Changelog

Release notes read the section matching their tag out of this file, so the
headings are `## Starling-X.Y.Z` — the tag name, exactly.

## Starling-3.1.3

The Chinese added in 3.1.2 went into a menu this console never puts on screen.
This puts it in the two menus that are actually reachable.

- **A Recently Played menu, next to Favorites.** The last twenty games
  launched, newest first, as a top-level entry of its own. It is assembled the
  way Favorites is -- a directory of empty `<System>.sub` files merging each
  system in, so a game is still launched by the system that owns it -- but the
  list itself cannot be stored the way favorites are. Favorites live in one
  file per system precisely so each system stays the single source of truth for
  its own games; recency is global and ordered, and rebuilding one order out of
  nineteen files would mean a timestamp beside every entry and a merge on every
  menu open. So it is one file, `recent.txt`, rewritten on each launch, whose
  line order *is* the record. It sits beside the playlist directories rather
  than inside one, because `addPlaylists()` loads every `.txt` it finds there
  into a `std::map` keyed by name -- which would sort the list alphabetically
  and throw away the only thing it stores. For the same reason `list.menuSort`
  is off for this collection alone. Writes go through the same
  temp-file-fsync-rename dance as favorites.txt, a game whose ROM has left the
  card is skipped rather than shown, and systems named nowhere in the list are
  not built at all -- building one costs a scan of its whole ROM directory.
  Artwork is provided for all thirteen themes.

- **The menu is bilingual wherever it is drawn.** The FunKey menu exists three
  times over, in three separate code bases: `funkeymenu.cpp` in gmenu2x, which
  is only reachable when gmenu2x is the launcher; `fk_menu.c` in picoarch, which
  is what the menu button raises inside a game; and `MenuMode.cpp` in RetroFE,
  which is what it raises in the library. 3.1.2 translated the first one, and a
  default install shows the other two. All three now carry matching rendering
  helpers and the same set of glosses: VOLUME 音量, BRIGHTNESS 亮度, SAVE 保存,
  LOAD 读取, ASPECT RATIO 比例, ADVANCED 高级, EXIT GAME 退出, POWERDOWN 关机,
  MOUNT USB 挂载, SET THEME 主题, SET LAUNCHER 启动器 -- down to the smaller
  lines beneath them: 确定吗, 保存中, 读取中, 处理中, 关机中, 存档位, 读取位,
  and the aspect ratio values. Proper nouns (GMENU2X, RETROFE) and user-supplied
  names (theme directories) are left alone, since neither has a translation to
  give. Matching, not shared: they are three copies in three independently
  patched trees, so each now carries a comment naming the other two, because a
  gloss changed in one of them and not the others is how the console ends up
  showing different Chinese depending on which menu you opened.
- **Bilingual lines are sized to fit the box they sit in.** The white panel
  behind a menu line is `MENU_BG_SQUARE_WIDTH`, 180px, while the text is centred
  over the full 240px screen -- so a line wider than 180px spills past both
  edges of the panel with nothing behind it. The English titles were already cut
  to fill that box (POWERDOWN alone very nearly does), so appending a gloss at
  the same point size overflowed by construction. Each line now renders at the
  largest rung of a five-step size ladder that fits, which leaves two thirds of
  them at exactly the size they have always been and steps the rest down one or
  two rungs. MANUAL ZOOM's gloss is 手动 rather than 手动缩放, being the one
  string that could not be made to fit at any rung.

- **picoarch and RetroFE declare the font they read.** Both open Droid Sans
  Fallback by absolute path, but neither selected `fonts-droid` -- the file was
  in the image only because gmenu2x happened to pull it in. Switching gmenu2x
  off would have taken the Chinese with it, and, since 3.1.2, RetroFE's fallback
  face for every character outside ASCII.

## Starling-3.1.2

Fixes to the 3.1.1 build, and the first Chinese in the interface.

- **picoarch cores build again.** Each core's make now runs single-job, with
  the parallelism moved up to the cores as a whole. A make handed its own `-j`
  advertises a job server in `MAKEFLAGS` to everything it runs, gcc included,
  then closes the pipe for the link -- and gcc 10's `lto-wrapper` believes the
  advertisement without checking, so picodrive's LTO link died every time. The
  new setting also honours `BR2_JLEVEL`, which the hard-coded `-j4` never did.
- **The in-game menu is bilingual.** VOLUME 音量, BRIGHTNESS 亮度, SAVE 保存,
  LOAD 读取, ASPECT RATIO 比例, EXIT GAME 退出, SET LAUNCHER 启动器,
  POWERDOWN 关机 -- each drawn from the layout font and the CJK fallback face
  on a shared baseline. RETROFE keeps its name.
- **RetroFE can render text outside ASCII at all.** It used to pre-render a
  glyph atlas of ASCII 32-127 and walk strings a byte at a time against it, so
  a Chinese character was three bytes that matched nothing and vanished
  silently. It now decodes UTF-8 and renders anything the atlas lacks on
  demand, falling back to Droid Sans Fallback for code points the theme font
  does not carry. A ROM whose filename is Chinese now shows up.

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

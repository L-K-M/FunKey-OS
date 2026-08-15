# FunKey-OS-Starling — Review (glm.md)

A full pass over the fork as of `76f461c` ("Do not put inline comments in commands meant to be pasted"), focused on the Favorites feature (the five RetroFE patches in `FunKey/package/retrofe/`), the OS plumbing around it, the 13 shipped themes, the artwork generator, the build/CI, and the docs. Findings are numbered, graded by severity and confidence, and each ends with a concrete, shovel-ready fix where one exists. An implementation log at the bottom records what was done with each item.

The fork itself is in good shape for something "unverified on hardware": the five patches are small, commented with the *reasons* for each change, and stack cleanly on the pinned upstream tag `RetroFE-FunKey-1.1.4`. TheFavorites design — per-system `favorites.txt` as the single source of truth, a `.sub`-aggregated menu that narrows to favorites — is genuinely the right architecture, and the "skip subcollections with no favorites" optimization is clever. What follows is mostly polish, two real bugs, and a set of speed/UX wins that would make Favorites feel first-class.

---

## 1. Bugs

### B1 — Subcollections leak on every visit to Favorites (HIGH, high confidence)

`RetroFE::getCollection()` (`FunKey/package/retrofe/0004-aggregate-favorites-collection.patch` + `0005`) builds a full `CollectionInfo` for every system that has favorites: ROM-directory scan, metadata injection, playlist load. These `subcollection` objects are stored only in a local `std::vector` that dies when the function returns; nothing ever `delete`s them.

- The aggregate collection *is* deleted when you leave the menu (`Page::cleanup()`), and its destructor deletes every `Item` it merged in — but the subcollection objects themselves (with their own `items` vectors of the very same pointers, their playlist maps, and ~15 strings per Item) are never freed.
- Concretely: each enter/leave cycle of **Favorites** leaks roughly the size of all favorited systems' item lists. On a library of ~2 000 ROMs that is on the order of 1–2 MB per visit. The V3s has 64 MB of DDR2 shared with the framebuffer and emulators; a user scrolling in and out of Favorites a dozen times can push the device into memory pressure for no gain.
- It is an upstream pattern (upstream FunKey never shipped a `.sub`-aggregated collection, so it never bit them), but the Favorites feature makes it user-visible on every session.

**Fix:** make the aggregate own its subcollections. Add `std::vector<CollectionInfo *> ownedSubcollections_` to `CollectionInfo`; `RetroFE::getCollection()` pushes each built subcollection onto the aggregate; `~CollectionInfo()` then, for each owned subcollection, calls `sub->items.clear()` (so the shared `Item` objects are only deleted once, by the aggregate's own `items` vector) and `delete sub`. Note the subcollections must outlive the aggregate anyway — `Item::collectionInfo` points at them (used by `Page::favoritesOwner()` for the write-back and by `Launcher::run()` for the launcher name), so they cannot simply be deleted early inside `getCollection()`.

### B2 — Unfavoriting inside Favorites leaves a stale entry (MEDIUM, high confidence)

When you press Y/X on a game *inside* the Favorites menu, `Page::removePlaylist()` erases the item from the aggregate's `favorites` playlist and from the owning system's, removes the `* ` marker, and shows the status message — but the list you are actually looking at is the narrowed **`all`** playlist (that is what `favoritesOnly` produces), and that vector is not touched. The game therefore stays in the Favorites list, now unmarked, until you leave and re-enter. On a system page the same behavior is correct (the list is "all games"); inside Favorites it reads as a bug because the list is defined as "favorites only".

**Fix:** in `Page::removePlaylist()`, when the erased item is also present in the currently displayed playlist vector (`playlist_->second`), erase it there too, then re-issue `menu->setItems(playlist_->second)` and `reallocateMenuSpritePoints()` for the active menus (the same dance `selectPlaylist()` does), taking care to clamp `selectedItem_`/scroll offsets when the selected row disappears. Failing that, a cheaper variant: keep the row but dim it and let it vanish on re-entry — but the full fix is not hard.

### B3 — `CollectionInfo::Save()` can insert and dereference a NULL playlist (LOW, high confidence)

`Save()` fetches `playlists["favorites"]` with `operator[]` — which inserts a NULL `vector*` if the key is absent — and immediately dereferences `saveitems->begin()`. Today every collection that can have `saveRequest == true` has had `addPlaylists()` run on it (which guarantees the key exists), so it is latent, but patch 0003's own `favoritesOf()` helper exists precisely because this map can hold NULLs; `Save()` should not be the one place that still creates them. `sortPlaylists()` has the same `playlists["all"]` pattern.

**Fix:** use `find()` and bail out with a `Logger::write(ZONE_WARNING, ...)` when "favorites" is missing or NULL. Three lines, removes a class of future crashes.

### B4 — README native-build instructions `cd` into a directory that is never created (LOW, high confidence)

"Build from source → Natively" says:

```
git clone https://github.com/L-K-M/FunKey-OS-Starling.git
cd FunKey-OS
make sdk all
```

The clone creates `FunKey-OS-Starling/`. Anyone pasting the block as written fails at the `cd`. (The Docker section's `docker cp starling:/home/funkey/FunKey-OS/images ./images` is correct — the container clones into `FunKey-OS` internally.)

**Fix:** `cd FunKey-OS-Starling`.

### B5 — `settings.conf` pins a theme that does not exist (LOW, high confidence)

`usr/games/settings.conf` says `layout = FunKey Style`. There is no `layouts/FunKey Style/` — the theme set here is `FunKey`, `FunKeyRed`, `FunKeyYellow`, …, and the theme that actually gets used is chosen by `layout.conf` (`RetroRoomCovers`), which `importCurrentLayout()` applies later and which erases/replaces the `layout` property. So the stale value is harmless *while `layout.conf` parses*. But if `layout.conf` is ever missing, empty, or unreadable (corrupted share partition, a user deleting it), RetroFE falls back to the `settings.conf` value and `loadPage()`/`loadSplashPage()` get a layout name with no directory — `PageBuilder` returns NULL and the frontend dies at boot. This is inherited from upstream FunKey S config drift ("FunKey Style" was the FunKey S default), but it is a landmine sitting in this fork's rootfs.

**Fix:** change the fallback to a theme that exists — `layout = RetroRoomCovers` (matches `layout.conf`, so behavior is unchanged) — or `layout = FunKey`. One-line change in the rootfs overlay.

### B6 — Y on the Main menu silently favorites *systems* (LOW, high confidence — behavior; MEDIUM as a UX question)

`togglePlaylist` runs at any menu depth. On the Main menu the selected item is a system entry whose `collectionInfo` is the Main collection, so pressing Y writes `Main/playlists/favorites.txt`, prefixes the system's title with `* ` (invisible in the image-based main menus of most themes), and shows "Added to favorites". Nothing corrupts — but nothing documents it either, and the README says Y marks "the highlighted game". Side effect: once a system is favorited this way, START on the Main menu switches to a favorites playlist of *systems* — a hidden, half-working "favorite systems" feature.

**Fix (pick one):** (a) suppress the toggle at `menuDepth_ == 0` / when `!selectedItem_->leaf`; (b) embrace it: document it as "favorite systems" in the README and let themes show the marker. (a) is the smaller, safer change; (b) is the more interesting feature but needs theme work to be visible.

---

## 2. General issues / robustness

### G1 — `favorites.txt` writes are not power-loss-safe (MEDIUM, high confidence)

`CollectionInfo::Save()` opens the real file and streams lines into it. The share partition is FAT; the console is a handheld whose users power off freely. A crash or power-cut mid-write leaves a truncated `favorites.txt` (partially written last line, lost earlier lines that lived past the truncate point). The current code does not even `flush()` explicitly before checking `good()` — `close()` happens first, which is what flushes, so the error check works, but the data still lands by ordinary buffered I/O with no durability.

**Fix:** write to `favorites.txt.tmp` in the same directory, `fsync()` it (open the temp path with `::open` + `::write`, or keep `ofstream` then `::open`+`::fsync` the path — on Linux `fsync` on a freshly `close()`d fd is what matters, so do the low-level write), then `::rename()` over the target and `fsync()` the directory. Rename-over-target is atomic on vfat. This makes favoriting survive an unlucky power-off, which for a feature whose whole point is "mark this so I can find it later" is worth the ~20 lines.

### G2 — Version strings live in four places (LOW, high confidence)

`Makefile` (`OS_VERSION = 3.0.0`), `etc/os-release` (five fields), `etc/sw-versions`, `etc/issue`. They agree today (3.0.0) but every release is four edits waiting to drift. A small `post-build.sh` step that seds `OS_VERSION` from the Makefile into the overlay files (or a buildroot `BR2_ROOTFS_OVERLAY` + `BR2_ROOTFS_POST_BUILD_SCRIPT` pattern that generates them) removes the class of bug.

### G3 — RetroFE patches are only validated by a full 2.5-hour OS build (MEDIUM, high confidence)

The five patches can break (upstream tag re-pins, patch drift, a typo) and the only signal is the end of a full buildroot run. Two cheap CI additions:

- **Apply-check** (guaranteed cheap): a workflow job that clones `FunKey-Project/RetroFE` at `RetroFE-FunKey-1.1.4`, `git apply --check`'s the series in order, and fails otherwise. Minutes.
- **Host compile** (best effort): same, then actually build `RetroFE/Source` on the runner with SDL1.2 dev packages, catching C++ errors. GStreamer is the awkward dependency; if the CMake refuses to build without it, the apply-check alone still pays for itself.

### G4 — `Item::fullTitle.at(0)` in `ReloadableText` "firstLetter" throws on empty titles (LOW, medium confidence)

`RetroFE/Source/Graphics/Component/ReloadableText.cpp` calls `selectedItem->fullTitle.at(0)` — `std::out_of_range` if a `fullTitle` is ever empty (empty `.conf`-fed menu item, weird ROM name). No shipped theme uses `firstLetter`, so it is latent; guard with `empty()` before `at(0)` if the type ever gets used.

### G5 — `frontend init` runs with output discarded and no failure surface (LOW, medium confidence; upstream)

`.profile` ends with `frontend init >/dev/null 2>&1 &` — if RetroFE dies at startup the user gets a silent black screen and no trace on the share partition. The README's "Getting logs out" section covers the manual workaround (repoint `log.txt`, redirect the frontend). A first-boot script could enable that redirection permanently; low priority since it needs the share partition mounted writable before login.

---

## 3. Performance

The device is a single-core Cortex-A7 (sun8i-v3s) with 64 MB RAM and an SD card; the frontend renders 240×240 via SDL1.2 software blits. Within that envelope:

### P1 — Entering Favorites rebuilds every favorited system from scratch (HIGH, high confidence)

The `collectionHasFavorites()` skip is a good optimization for systems with *no* favorites, but for every system that *has* at least one, `getCollection("Favorites")` runs the full pipeline: `ImportRomDirectory` (readdir + per-file item construction for every ROM on the card), `injectMetadata` (a SQLite query per system plus per-item map lookups), sorting, playlist matching. For MAME/FBA libraries of 1 000+ entries this is easily multiple seconds — and it runs on *every* entry, because nothing is cached between visits (and see B1: the previous attempt is still in memory, leaked). Favorites is also the **first** entry of the Main menu, so it is the easiest menu to hit by accident.

Layered fixes, in increasing ambition:

- **P1a — Skip metadata injection for items that cannot be shown.** `injectMetadata(subcollection)` runs before the favoritesOnly narrowing, so metadata is injected for every ROM in every favorited system even though only the favorites are displayed (and only they need pretty titles). For the aggregate, inject only for items present in the favorites playlist. (The metadata pass also *overwrites titles*, so ordering matters: narrow first, then inject, then re-mark.) Moderate, self-contained in `getCollection`.
- **P1b — Cache the Favorites aggregate.** The playlist file stores only names, which is why a scan is needed at all. A small cache next to the playlists (e.g. `userPath/collections/Favorites/cache.txt`) recording `system|name|title|filepath` per favorited game, rewritten whenever favorites change (the same hook as `Save()`), lets `getCollection("Favorites")` build `Item`s directly — no ROM scan, no metadata — with a cheap validity check (compare each system's `favorites.txt` mtime against the cache; on mismatch, fall back to today's full path). This is what makes Favorites open as fast as any system menu. It needs care around launch (`Item::collectionInfo->launcher`), solvable by keeping a lightweight per-system `CollectionInfo` shell alive for the aggregate. Bigger change (~150 lines), highest payoff.
- **P1c — `std::set` for the narrowing membership test.** The `favoritesOnly` filter does `std::find` over the favorites vector for *every* merged item — O(n·m). Build `std::set<Item*>` (or `unordered_set`) once. Same for `addSubcollectionPlaylist`'s linear contains-check. Trivial; matters when n is the whole library.

### P2 — `sortItems()` re-lowercases titles on every comparison (MEDIUM, high confidence; upstream)

`itemIsLess` calls `lowercaseFullTitle()`, which constructs and transforms a fresh `std::string` per side per comparison. Sorting the merged Favorites library (or any big system) is O(n log n) string allocations. A cached lowercase key on `Item` (invalidated nowhere — titles only change at load/mark time, and the marker deliberately lives in `title` not `fullTitle`) or a decorate-sort-undecorate in `sortItems` removes it. Upstream issue, made worse by Favorites aggregating the whole library.

### P3 — `sortPlaylists()` is a nested loop (LOW, medium confidence; upstream)

Orders each playlist by walking `all` × playlist-members. Fine at favorites scale (tens), irrelevant at library scale because "all" is narrowed — only worth touching if P1b lands without narrowing.

### P4 — SDL music/sfx chunk loading and per-frame text measurement are upstream behavior (INFO)

`Text::draw` measures per character per frame and the status bar re-sets its string every frame (`setText` is a cheap assignment; no texture churn). Not worth touching on a 240×240 screen; noted only so nobody red-flags them later.

---

## 4. Missing features

### M1 — gmu (music player) is disabled to make the OS build (MEDIUM, high confidence)

`BR2_PACKAGE_GMU` is unset in `funkey_defconfig` (commit 29e4b94, which also documents the root cause and the fix path: the package was written for a hand-installed SDK at `/opt/FunKey-sdk`; its vendored FLAC/WavPack configure uses `--host=arm-funkey-linux-musleabihf`, which matches none of buildroot's `arm-linux-*` wrappers, so it silently built x86_64 libraries and failed the link). The commit message already sketches the fix: use buildroot's own `BR2_PACKAGE_FLAC`/`BR2_PACKAGE_WAVPACK` (both already enabled in the defconfig) from `STAGING_DIR`, or rewrite the triplet to `--host=arm-linux` exactly as `st-sdl.mk` does. A working music player is a real feature of the stock OS that this fork currently lacks.

### M2 — Empty Favorites gives no guidance (MEDIUM, high confidence)

A fresh user opens Favorites (first menu entry!) and gets an empty list with no hint that Y is how you fill it. The plumbing to fix this already exists: when entering a favoritesOnly collection whose playlists are all empty, call `setStatusMessage("No favorites yet — press Y on a game", 3.0f)` from the collection-push path. Themes with a `statusText` (all 13) show it; the message self-clears. ~10 lines.

### M3 — No favorites count anywhere (LOW, high confidence)

Neither the Main menu tile nor the Favorites page tells you how many favorites exist. Cheapest useful version: include the count in the toggle acknowledgements ("Added to favorites — 12 total") and/or show it in the status message when entering Favorites ("12 favorites across 4 systems"). A themed badge on the Favorites artwork would need a new reloadable-text type (C++); the message version does not.

### M4 — "Recently played" is the obvious sibling feature (MEDIUM as an idea)

The playlist machinery is generic (`addPlaylist`/`removePlaylist` write any `playlists/<name>.txt`); Favorites just happens to be the one exposed. A `recent` playlist appended by `Launcher::run()` (prepend item name, cap at ~20, save) plus a `Recent` collection with `.sub` files and a `list.favoritesOnly`-style narrowing for "recent" would reuse ~90% of the Favorites architecture and is exactly the kind of thing a 1-inch-screen user wants (resume what you played yesterday). Needs a config knob for the narrowing ("playlistsOnly = recent") — currently `favoritesOnly` is favorites-hardcoded.

### M5 — Play counts / "most played" (LOW as an idea)

Same plumbing as M4 with a counter file; display as a playlist. Lower value than Recent; keep on the list for later.

### M6 — Boot straight into Favorites (LOW, high confidence it works)

`firstCollection = Main` in settings.conf. A documented variant (`firstCollection = Favorites`) boots into the mixed list of everything you actually play — for a favorites-centric user that is the whole console. Zero code; either a README note or a Settings entry (GMenu2X side).

### M7 — README documents only the favorites keys, not the rest of the pad (LOW, high confidence)

Undocumented but wired: L/R shoulder = jump by letter (`letterUp`/`letterDown` = N/M), FN alone = random game launch (`random = K`, and fkgpiod maps bare FN to KEY_K), MENU = system menu, START in a system toggles favorites/all *within that system*. A short "Button map" table in the README would answer the first three questions any new owner has. (Also worth stating in that table: X removes, Y toggles, so Y alone suffices.)

### M8 — Themes without a clock could have one for free (LOW, high confidence)

`reloadableText type="time"` exists and refreshes every update; only the FunKey/FunKeyRed/FunKeyYellow family uses it. TFT, Classic, Flat, DarkUI, etc. have status bars with room. Theme-only change; nice quality-of-life on a device with no other clock.

### M9 — The "4/128" game-index indicator is sitting commented-out in the FunKey theme (LOW, high confidence)

The `collectionIndexSize` block in `FunKey/layout.xml` is commented out. `getCollectionSize()`/`getSelectedIndex()` are wired for it. Re-enabling (in whatever corner the theme can spare) gives immediate orientation in long lists. If it was disabled because the narrowed Favorites list reports confusing numbers, that is worth checking on-device — but the mechanism is there.

---

## 5. Visual issues and layout problems

### V1 — statusText can overlap the bottom game row (LOW, medium confidence)

All 13 themes place `<statusText>` at y=224 (centered). In the FunKey family the sub-menu rows sit at y = 54/114/174/234 with 14px text at x≥70; the bottom row spans roughly y 226–242 and the message spans ~217–231 — a few pixels of potential overlap in the x-range where both exist, for 1.5 s. On the whole it is benign (transient, top layer), but nudging to y≈228 with the layout's smaller font, or adding a semi-transparent pill behind it, would remove the collision entirely. Check per-theme; some (TFT, Classic) may have nothing at y≈224.

### V2 — The `* ` marker is functional but drab (LOW, high confidence)

The ASCII choice is well-reasoned (any font, no missing-glyph failure mode) and the `title`-not-`fullTitle` decision avoids sort-jumps and file pollution — both documented in the patch and both correct. Still: a filled star `★ ` reads instantly on a 1-inch screen in a way `* ` does not, and every shipped theme carries a real TTF (OpenSans/Roboto/Cabin/Gilroy/markpro). A safe hybrid: keep the ASCII constant as the marker *default*, and add a per-theme font-glyph probe at startup (Font already has `getRect`), or simply verify the nine shipped fonts contain U+2605 and switch the constant then — with the ASCII fallback for user themes verified not to. (The `tools/gen-favorites-artwork.py` star already sets the visual vocabulary: gold.)

### V3 — Marked titles lose two characters of width in narrow lists (LOW, medium confidence)

In `reloadableScrollingText`-style rows the marker scrolls with the title; in fixed-width rows it eats into the truncation budget. Cosmetic; acceptable. The only per-item color alternative would need Text-component support for item-conditional colors — not worth the churn now, revisit if a theme wants it.

### V4 — The status message pops in and out with no animation (LOW, high confidence)

`setStatusMessage` swaps the string instantly and clears it 1.5 s later. A 150–200 ms alpha fade at both ends (drive `textStatusComponent_->baseViewInfo.Alpha` from `statusMessageTime_` in `Page::update()`, cheap arithmetic, no tween machinery needed) would make it feel designed rather than debugged. Pair with V1's pill and the feature starts feeling native.

### V5 — Generated Favorites artwork: good, with two nits (LOW, high confidence)

The generator is genuinely nice work — palette sampling with self-output exclusion, supersampled star, per-theme fonts/sizes, idempotent by construction, and it *fails the run* on fallback fonts. Nits: (1) it is not run in CI, so nothing holds the committed PNGs to the generator's output — a `pip install pillow && python3 tools/gen-favorites-artwork.py <dir> && git diff --exit-code` job would pin them (pin Pillow's version in the job to keep LANCZOS output stable); (2) `THEMES` hardcodes per-theme file lists that will silently miss a future theme's new artwork name — acceptable, since a missing theme is reported but a missing *file* within a known theme is not; a warning when a theme's existing `system_artwork` file list contains names the spec does not generate would close that.

---

## 6. User experience / interface

### U1 — No audio feedback on toggle (LOW, high confidence)

Y/X are silent; the only feedback is a marker and a text line. The sound chunks are already loaded per-theme (`select`/`highlight`); playing the highlight chunk (or a dedicated optional `<sound type="favorite">` with fallback) on toggle is a few lines in `Page::togglePlaylist()` and matches the theme's existing audio vocabulary. Small, delightful.

### U2 — Unfavoriting the last favorite while viewing that system's favorites playlist (LOW, high confidence; mostly upstream)

The item stays on screen (the playlist switcher refuses empty playlists) with the marker removed. Related to B2; the same re-sync mechanism fixes both if it lands.

### U3 — Favorites being the *first* Main entry maximizes exposure to the slowest menu (MEDIUM as UX, ties to P1)

With P1b (cache) this stops mattering. Without it, consider moving Favorites after the systems, or keeping it first only once it opens instantly. No action needed if P1 lands.

### U4 — `rememberMenu` restores playlist state per collection name (INFO)

`lastMenuPlaylists_` keys on collection name, so Favorites reopens on "all" (narrowed) — consistent. No issue found; noting that the interaction was checked.

### U5 — The toggle is undetectable in image-only main menus (ties to B6)

If B6 is resolved by suppressing depth-0 toggles, this evaporates. If embraced as "favorite systems", themes need marker visibility (text fallback) for it to be usable.

---

## 7. Aesthetics

### A1 — Status message styling is inherited, not designed (LOW)

The message uses the layout's default font/size/position (center, y=224, white). Giving it its own smaller size, letter-spaced caps, and the artwork generator's gold (`#F0A312`/`#FFD65C`) would tie the on-screen feedback to the Favorites star iconography already shipped in every theme. Theme-only change (statusText already takes font attributes).

### A2 — Fade the marker in (LOW)

When Y marks a game the `* ` appears on the next frame — instant string swap. Fading just the marker would need component support; not worth it alone, fold into any future marker work (V2).

### A3 — Splash consistency (INFO)

`splash.xml` files have no statusText (correct — no favorites actions during splash) and no Favorites-specific art is needed there. Checked; nothing to do.

### A4 — The gold star system artwork is the strongest visual asset the feature has (INFO)

If V2 (star glyph) lands, the marker/star/artwork become one consistent gold-star language across the UI — that coherence is the aesthetic win to aim for.

---

## 8. Novel / cool / quirky ideas

### N1 — "Star Log": favorites with timestamps, newest first

Persist `name|unixtime` when favoriting (same file, extra column — backward-compatible parse), and offer a "Recently starred" ordering in the Favorites menu. Turns Favorites from a static bucket into a light history. Small, uses only existing plumbing; the narrowing already rebuilds from playlists.

### N2 — Random-from-favorites (already half-there)

The `random` key (bare FN) picks from the *current list* — so inside Favorites, FN already means "surprise me from my favorites". Document it next to the button map (M7) and it becomes a feature with zero code. A dedicated "Shuffle" entry as the last row of the Favorites list (a synthetic Item launching a random favorite) is the flashy version.

### N3 — Boot animation easter egg for Favorites

The splash already shows per-boot; a variant that twinkles a star when favorites exist (count shown as N stars) is pure charm, cheap in the artwork pipeline, and reinforces the feature. Low priority, high smile.

### N4 — "Kiosk mode" via favorites-only boot

First-boot devices with a curated favorites set (parents loading 10 games for a kid) — boot straight into Favorites (M6) plus a settings toggle to hide the system menus entirely. The plumbing (firstCollection + exitOnFirstPageBack) already exists in settings.conf.

### N5 — Auto-screenshot favorites

fbgrab exists in the image (BR2_PACKAGE_FBGRAB). On game exit, if the game is a favorite, stash `screenshot.png` next to the ROM; themes with `artwork_front` fallback already prefer box art but the screenshot path exists in the media config. Gives favorites covers for games that shipped without art. Moderate; charming.

---

## 9. Build / CI / repo hygiene (quick hits)

- **H1** — `Makefile` `print-artifacts` is good single-source design; extend the same thinking to G2 (version strings).
- **H2** — `zai-code-review.yml` is correctly scoped (same-repo branches only, pinned commit, no-op without the secret). Nothing to change.
- **H3** — `build.yml` paths-ignore logic is right (docs-only pushes skip). If G3 lands, add `FunKey/package/retrofe/**` as a trigger for the fast patch job.
- **H4** — `docker/Dockerfile` default ref tracks `master` ✓; the README Docker section and native section now disagree only on the `cd` bug (B4).
- **H5** — `tools/gen-favorites-artwork.py` — add the CI idempotence check (V5) and it becomes a proper regression test for the artwork.

---

## Priorities (if only a few things get done)

1. **B1** (leak) — correctness of the flagship feature on a 64 MB device.
2. **P1c + B3** (set-based narrowing; NULL-safe Save) — trivial diffs, real robustness.
3. **B2** (stale entry in Favorites) — the most user-visible wart.
4. **M2 + V4 + U1** (empty-state hint, fade, sound) — makes the feature feel finished.
5. **G1** (atomic save) — cheap insurance for the thing users would be angriest to lose.
6. **P1a/P1b** (skip metadata; cache) — makes the first menu entry the fastest one.
7. **M1** (gmu) — restore parity with stock OS.
8. **B4/B5/M7** (docs + config hygiene) — an afternoon of good.

---

## Implementation log

Filled in as items are implemented; each entry links its PR. (Do-not-merge policy per task instructions: PRs are left open at steady state.)

| Item | Branch | PR | State |
| --- | --- | --- | --- |
| B4 + M7 (README cd fix + button map) | `docs/readme-build-and-buttons` | [#24](https://github.com/L-K-M/FunKey-OS-Starling/pull/24) | Open, no feedback |
| B1 + B3 + P1c/P1d + G1 (leak, NULL-safe save, set membership, atomic save) | `retrofe/favorites-robustness` | [#25](https://github.com/L-K-M/FunKey-OS-Starling/pull/25) | Open, no feedback |
| B2 (unfavorited game leaves the view) | `retrofe/unfavorite-leaves-view` | [#26](https://github.com/L-K-M/FunKey-OS-Starling/pull/26) | Open, no feedback |
| M2 + V4 (empty-Favorites hint, message fade) | `retrofe/empty-favorites-hint` | [#27](https://github.com/L-K-M/FunKey-OS-Starling/pull/27) | Open, no feedback |
| B5 (valid layout fallback) | `config/valid-layout-fallback` | [#28](https://github.com/L-K-M/FunKey-OS-Starling/pull/28) | Open, no feedback |
| G3 apply-check half (fast patch-series CI) | `ci/retrofe-patch-check` | [#29](https://github.com/L-K-M/FunKey-OS-Starling/pull/29) | Open, no feedback |
| M1 (re-enable gmu via buildroot libs) | `package/re-enable-gmu` | [#30](https://github.com/L-K-M/FunKey-OS-Starling/pull/30) | Open, no feedback — CI may yet fail in a new place, see PR body |
| B6 option (a) (Y/X only on games) | `retrofe/games-only-favorites` | [#31](https://github.com/L-K-M/FunKey-OS-Starling/pull/31) | Open, no feedback |
| P2 (cache lowercase sort keys) | `retrofe/cache-lowercase-titles` | [#32](https://github.com/L-K-M/FunKey-OS-Starling/pull/32) | Open, no feedback |

Notes on the PR flow: the PRs were first opened from the `BigBoyDevBox` fork
(no write access was assumed at the time), where the automated GLM 5.2 review
(`.github/workflows/zai-code-review.yml`) is structurally skipped — it only
runs for same-repo branches — and were then re-opened from same-repo branches
(#15–#23 closed in favour of #24–#32) so the review could run. Watch those
for feedback; if none arrives, each PR is at “steady state, no useful
feedback arrives” and is left open.

# FunKey-OS-Starling — Analysis & Backlog (ANALYSIS.md)

This is the working backlog for future work on the fork: every finding from the
full review passes (preserved in `glm.md` and `kimi.md` — two independent
reviews, consolidated here) that is **not yet implemented**, plus a status
table of what was implemented and where it is waiting. Items are written to be
picked up directly — context, evidence, concrete fix plan, risk — without
needing to re-derive the review.

Repository facts an implementer needs: default branch is `master` (there is no
`main`); RetroFE changes are carried as a patch series in
`FunKey/package/retrofe/` applied by buildroot in glob order against the tag
pinned in `retrofe.mk` (`RetroFE-FunKey-1.1.4`); the console is a single-core
Cortex-A7 (sun8i-v3s) with 64 MB RAM, a 240×240 screen, SDL1.2 software
rendering, and the share partition (where playlists live) is FAT; a full OS
build takes 1.5–3 h in CI, so `FunKey/package/retrofe/**` changes should be
smoke-checked with the fast apply-check workflow first.

---

## Status of implemented work (in flight, do not re-implement)

All of these have open PRs on same-repo branches (so the GLM review workflow
runs on them), verified to apply cleanly (standalone and stacked where files
overlap). CI builds sit in `action_required`/`queued` pending maintainer
approval, so treat the CI verdict as pending, not failed. If a PR is rejected,
the analysis for it lives in `glm.md`/`kimi.md` and the patch itself in the PR
branch.

| What | Item | PR |
| --- | --- | --- |
| Subcollection leak on every Favorites visit; NULL-safe `Save()`; set-based narrowing/merge; power-loss-safe atomic favorites save | B1, B3, P1c, P1d, G1 | [#25](https://github.com/L-K-M/FunKey-OS-Starling/pull/25) |
| Unfavorited game leaves the list on screen (narrowed views) | B2 | [#26](https://github.com/L-K-M/FunKey-OS-Starling/pull/26) |
| Empty-Favorites hint + status-message fade | M2, V4 | [#27](https://github.com/L-K-M/FunKey-OS-Starling/pull/27) — see review comment: short messages may only ever render at ~8% alpha on idle menus; #45's dirty-flag or #42's OSD route are the fixes |
| Y/X no longer favorite menu entries (games only) | B6(a) | [#31](https://github.com/L-K-M/FunKey-OS-Starling/pull/31) |
| Cache lowercase sort titles (sort-time allocations) | P2 | [#32](https://github.com/L-K-M/FunKey-OS-Starling/pull/32) |
| Valid layout fallback in `settings.conf` | B5 | [#28](https://github.com/L-K-M/FunKey-OS-Starling/pull/28) |
| README native-build `cd` fix + full button map | B4, M7 | [#24](https://github.com/L-K-M/FunKey-OS-Starling/pull/24) |
| Fast RetroFE patch-series CI apply-check | G3 (apply half) | [#29](https://github.com/L-K-M/FunKey-OS-Starling/pull/29) |
| gmu re-enabled against buildroot's FLAC/WavPack | M1 | [#30](https://github.com/L-K-M/FunKey-OS-Starling/pull/30) |
| Drop ~4.4 MB of unreferenced files (splash_BAK/device_BAK/tmp/ico) + `rememberMenu` duplicate + `menu.txt` newline | K1 | [#41](https://github.com/L-K-M/FunKey-OS-Starling/pull/41) |
| Favorite-toggle feedback via the kernel notification overlay (fbtft OSD) — kills the statusText/title overlap on device | K2 (V1 done properly) | [#42](https://github.com/L-K-M/FunKey-OS-Starling/pull/42) |
| Per-item owning system in the Favorites status bar ("NES" instead of "Favorites") | K3 | [#43](https://github.com/L-K-M/FunKey-OS-Starling/pull/43) |
| `share`: N-file `.fwu` glob fix + removal of the never-run `.swu` loop | K4 | [#44](https://github.com/L-K-M/FunKey-OS-Starling/pull/44) |
| Lighter toggle refresh: rebuild one slot instead of the whole wheel + statusMessageDirty_ render fix | K5 | [#45](https://github.com/L-K-M/FunKey-OS-Starling/pull/45) |

Closed as superseded (second review produced duplicates; the better version
won): fork PRs #33–#40 → same-repo #41–#45; #35 (hint) → #27; #37 (leak) →
#25; #38 (atomic save) → #25.

**Patch numbering.** #25–#32 carry the 0006–0009 patch series (plus per-PR
0006 singles); the second review's kept patches are numbered 0020–0022 to stay
clear of them. Textual interplay: #42 rewrites `setStatusMessage()` (also
edited by #27); #45 rewrites `togglePlaylist()` (also edited by #31) and adds
a line in `update()` (near #27's fade block); #26 and #45 are adjacent around
`removePlaylist()`. Whichever lands second in each pair needs a small rebase
in `Page.cpp` — noted in the PR bodies.

If any of these PRs land, delete the row. If one is closed unmerged, move its
item back into the backlog below and fold in whatever the review said.

---

## High-value, well-specified, not yet implemented

### 1. Make Favorites open instantly — cache the aggregate (was P1b)

**Problem.** Entering Favorites rebuilds every favorited system from scratch on
every entry: `ImportRomDirectory` (readdir + Item construction for every ROM on
the card), `injectMetadata`, sorting, playlist matching. For 1 000+ ROM
libraries this is seconds — and Favorites is the *first* Main-menu entry, so it
is the easiest to hit by accident. The existing
`collectionHasFavorites()` skip only helps systems with zero favorites.

**Why a scan is needed at all.** `favorites.txt` stores only item *names*; to
display and launch a game RetroFE needs its `filepath` and owning collection —
which only a directory scan produces.

**Plan.**

1. On every favorites write (same hook as `Save()`), also write
   `userPath/collections/Favorites/cache.txt` with one line per favorited game:
   `system|name|title|filepath`.
2. On entering a `favoritesOnly` collection, stat each system's
   `favorites.txt`; if every mtime is ≤ the cache's, build `Item`s straight
   from the cache — no ROM scan, no metadata pass. On any mismatch or missing
   cache, fall back to today's full path (which then refreshes the cache).
3. `Item::collectionInfo` must point at a live `CollectionInfo` for the system
   (launch resolves the launcher through it; so does the favorites write-back).
   Keep lightweight per-system shells alive for the aggregate's lifetime — the
   ownership machinery in #25 (`ownSubcollection()`) is exactly the
   right place to hang this.
4. Deleting a favorite invalidates one line and one mtime; a card edited on a
   computer simply falls back to the slow path once.

**Risk.** Medium: title/filepath staleness if the cache logic misses a path;
mitigated by the mtime check and the automatic fallback. **Payoff:** the
highest of anything on this list — the flagship feature stops being the
slowest menu.

### 2. Skip metadata injection for games that cannot be shown (was P1a)

**Problem.** `cib.injectMetadata(subcollection)` runs on every system with
favorites, for **every** ROM in it, before the `favoritesOnly` narrowing drops
all but the favorites. Metadata (SQLite query + per-item map lookups, and title
reassignment) is only needed for the games that will be displayed.

**Plan.** In `RetroFE::getCollection()`, for a `favoritesOnly` aggregate:
narrow first (set-based membership against the merged items), then run
`injectMetadata` per subcollection with the injection limited to items in that
subcollection's favorites playlist, then apply the favorite markers.
`MetadataDatabase::injectMetadata` works per collection over
`collection->items`; either give it an item-filter parameter or (simpler)
temporarily point the subcollection's item list at its favorites only for the
duration of the call. Order matters: metadata overwrites titles, so markers go
on **after** injection.

**Risk.** Low-medium: ordering interactions with marker/sort logic; covered by
thinking through load-order once. Worth doing even after item 1, since the
cache fallback path still scans.

### 3. Recently played — the obvious sibling feature (was M4)

The playlist machinery is generic (`addPlaylist`/`removePlaylist` write any
`playlists/<name>.txt`); Favorites is merely the one exposed. A `recent`
playlist gives the 1-inch-screen user the thing they actually want — resume
what they played yesterday.

**Plan.**

1. In `Launcher::run()` (or wherever the launch is reaped), prepend the
   launched item's name to its collection's `playlists/recent.txt`, cap at
   ~20, write back (reuse the atomic save path from #25).
2. Generalize the `favoritesOnly` narrowing into `playlistsOnly = <name>` so
   any playlist can drive an aggregate view (today the narrowing and the skip
   check are favorites-hardcoded in `getCollection()` — `collectionHasFavorites`
   and the marker loop both say "favorites" literally).
3. Ship a `Recent` collection: `.sub` files like Favorites, `playlistsOnly =
   recent`, a menu entry below Favorites, artwork generated by extending
   `tools/gen-favorites-artwork.py` (wordmark "RECENT", clock-rewind glyph).

**Risk.** Medium — mostly the generalization in step 2, which touches the
narrowing code #25/#26 also touch. Land those first.

### 4. gmu follow-up, if #30 fails in CI (was M1, remainder)

#30 re-enables gmu using buildroot's own FLAC/WavPack. The honest expectation
(written in its body) is that the build may die somewhere *new* — the previous
failures never got past the vendored libraries. If CI rejects it: the failure
will be specific (a frontend, the OPK step, a runtime path); fix that spot the
same way `st-sdl.mk` was fixed, and keep the defconfig flip in a separate
commit from the `gmu.mk` fix so only the first has to be reverted.

---

## Quick wins (small, safe, high certainty)

### 5. Sound feedback on favorite toggle (was U1)

Y/X are silent; the only feedback is the marker and the text line. The theme's
sound chunks are already loaded (`select`/`highlight`). Play the highlight
chunk from `Page::togglePlaylist()` — or add an optional
`<sound type="favorite"/>` to `PageBuilder`'s known types with fallback to
highlight. A few lines; matches each theme's existing audio vocabulary.

### 6. Favorites count in the acknowledgement (was M3, cheap half)

Include the total in the toggle messages — "Added to favorites — 12 total" —
from `favoritesOf(owner)->size()` after the change. Pure string work on top of
the existing `setStatusMessage()`. (The badge-on-artwork version needs a new
reloadable-text type; keep that for later.)

### 7. Boot straight into Favorites (was M6)

`firstCollection = Main` in `usr/games/settings.conf`. A documented variant
(`firstCollection = Favorites`) boots into the mixed list of everything the
user actually plays. Zero code — README note now, a GMenu2X Settings toggle if
one is ever wanted. Test on-device that `getCollection("Favorites")` at boot
behaves (empty-favorites case is handled by #27's hint).

### 8. Clocks for the themes that lack one (was M8)

`reloadableText type="time"` exists and self-refreshes; only the
FunKey/FunKeyRed/FunKeyYellow family uses it. TFT, Classic, Flat, DarkUI,
Daijismol, Artbook-sml, GameBoy, PixxelPlus, RetroRoomCovers, Superlopez have
status bars with room. Theme-only change — add the element with the theme's
own font/colour, no C++.

### 9. Game-index indicator ("4/128") in the FunKey theme (was M9)

The `collectionIndexSize` block in `FunKey/layout.xml` is commented out; the
plumbing (`getCollectionSize()`/`getSelectedIndex()`) is wired. Uncomment,
position in a spare corner, and check on-device that the narrowed Favorites
list doesn't report confusing numbers — that suspected confusion may be why it
was disabled.

### 10. Version strings from one place (was G2)

`Makefile` (`OS_VERSION`), `etc/os-release` (five fields), `etc/sw-versions`,
`etc/issue` all carry 3.0.0 by hand. A `post-build.sh` step that seds
`OS_VERSION` into the overlay files removes the four-places-to-drift class of
bug. Keep `print-artifacts` as the model: one source, everything else derived.

### 11. Host-compile half of the patch CI (was G3, compile half)

#29 covers "does the series apply". The second half is "does it compile":
clone RetroFE at the pinned tag on the runner, apply the series, build
`RetroFE/Source` with SDL1.2 dev packages (`libsdl1.2-dev libsdl-image1.2-dev
libsdl-mixer1.2-dev libsdl-ttf2.0-dev libsdl-sound1.2-dev` + glib/sqlite/zlib +
gstreamer, which is the awkward one). If CMake refuses without gstreamer,
`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev` on ubuntu-latest is
enough for a compile-only gate (`cmake` + `make -j`, no linking of the FE
against device libs). Best-effort job, allowed to be flaky; the apply-check
stays the guaranteed gate.

### 12. Artwork idempotence check in CI (was V5/H5)

`tools/gen-favorites-artwork.py` is deterministic by construction; nothing
holds the committed PNGs to its output. A job that installs a *pinned* Pillow,
runs the generator against the layouts tree, and `git diff --exit-code`s
catches both generator regressions and hand-edited artwork drift. Pin the
Pillow version so LANCZOS output stays byte-stable. Optional extra: warn when
a theme's existing `system_artwork` file names are not covered by the
generator's `THEMES` spec — a missing *theme* is reported today, a missing
*file* is not.

---

## Polish (visual / UX), not yet implemented

### 13. Star glyph marker instead of `* ` (was V2)

The ASCII `* ` marker was chosen for fallback-font safety and the choice is
documented in patch 0005. A filled star `★ ` (U+2605) reads instantly on a
1-inch screen and matches the gold star artwork every theme already ships.
**Blocker:** whether each of the nine shipped theme fonts actually contains
U+2605 has never been verified, and `Text::draw` silently skips missing
glyphs — a font without it would render a one-space indent and no marker at
all, i.e. exactly the bug the marker exists to prevent. Verify with
`fontTools` (`pip install fonttools; ttx -t cmap <font>.ttf | grep 2605`)
across all nine fonts first; if any lack it, either subset-extend them or keep
ASCII. Keep `favoriteMarker` a single constant either way.

### 14. Status-message styling (was V1, A1)

- `statusText` sits at y=224 in all 13 themes; in the FunKey family the bottom
  game row spans ~226–242 at x≥70 — a few pixels of transient overlap. Nudge
  to y≈228 with the layout's smaller font, or add a semi-transparent pill
  behind the text. (In the four wheel themes it is a dead-on collision, not a
  few pixels — see K6. If #42 lands, all of this matters only off-device.)
- The message inherits the layout's default font/size/colour. Giving it its
  own smaller size, letter-spaced caps, and the artwork generator's gold
  (#FFD65C/#F0A312) ties on-screen feedback to the Favorites star iconography
  already in every theme. Theme-only change — `statusText` already accepts
  font attributes. Do this together with #13 for one coherent "gold star"
  language.

### 15. Marker width in narrow lists (was V3)

`* ` (or `★ `) consumes two characters of truncation budget in fixed-width
rows and scrolls with the title in scrolling rows. Cosmetic and acceptable
today; the only real fix (per-item colour) needs Text-component support for
item-conditional colours — not worth the churn unless a theme asks.

---

## Larger ideas (worth a design pass, not shovel-ready)

### 16. Play counts / most-played playlist (was M5)
Same plumbing as Recent (item 3): a counter file per system incremented on
launch, a `mostplayed` playlist, an aggregate view. Lower value than Recent —
a design pass should decide whether both lists earn their menu slots on a
240×240 screen.

### 17. Star Log — favorites with timestamps (was N1)
Persist `name|unixtime` when favoriting (backward-compatible parse: extra
column, readers take the first token), offer "Recently starred" ordering in
Favorites. Small, uses only existing plumbing; the narrowing already rebuilds
from playlists.

### 18. Random-favorite as a feature (was N2)
Bare FN already launches a random game from the current list — inside
Favorites that *is* "random favorite", undocumented. Cheap: document next to
the button map. Flashy: a synthetic "Shuffle" row as the last entry of the
Favorites list that launches a random favorite.

### 19. Favorites boot animation easter egg (was N3)
A splash variant that twinkles a star per favorite when any exist. Pure charm,
cheap in the artwork pipeline, low priority.

### 20. Kiosk mode via favorites (was N4)
First-boot devices curated for a kid: `firstCollection = Favorites` (item 7)
plus a documented combo of `exitOnFirstPageBack` and a pruned `menu.txt` that
hides system menus entirely. All config, no code; needs a careful README
section about how to undo it.

### 21. Auto-screenshot favorites (was N5)
`fbgrab` ships in the image. On game exit, if the game is a favorite, stash a
`screenshot.png` next to the ROM; the media config already has a screenshot
path themes can use. Gives favorites covers for games that shipped without
art. Moderate; needs care around FBGrab timing on exit and SD write cost.

---

## Latent upstream issues (fix opportunistically, low priority)

### 22. `ReloadableText` "firstLetter" crashes on empty titles (was G4)
`selectedItem->fullTitle.at(0)` throws `std::out_of_range` on an empty
`fullTitle`. No shipped theme uses `firstLetter` today; guard with `empty()`
before `at(0)` if the type ever ships in a theme.

### 23. Frontend failure has no surface (was G5)
`.profile` ends with `frontend init >/dev/null 2>&1 &` — a RetroFE startup
death is a silent black screen. The README documents a manual log redirect; a
first-boot script could make that permanent (repoint `log.txt` at the share
partition and stop discarding the frontend's output). Needs the share
partition mounted before login — check `S10share` ordering first.

### 24. `sortPlaylists()` NULL-"all" pattern (was B3's sibling)
`sortPlaylists()` still fetches `playlists["all"]` with `operator[]` — the
same insert-NULL pattern #25 removed from `Save()`. Every collection that
reaches it has "all" (set by `buildCollection()`), so it is latent; fix the
same way if touched for other reasons.

---

## Additional findings from the second review (`kimi.md`)

A second, independent full review (same scope, same pinned tag) was done in
parallel; its full text is `kimi.md`. Findings that duplicate items above were
consolidated into them; the PRs it produced are in the status table (K1–K5).
What remains unique and unimplemented:

### K6. V1 is understated for the wheel themes (evidence, not a task)

The statusText/title overlap is not "a few pixels": in the four wheel themes
(the shipped default included) the title strip is centered at y≈223 and the
statusText at y=224 — same size, same colour, same spot, and Text components
overdraw rather than clear. It is a dead-on collision for 1.5 s. If #42 lands
this is moot on device; on desktop it remains. See `kimi.md` B1 for the
per-theme measurements.

### K7. `foreground.png` on layer 20 is silently never drawn (wheel themes)

`Page::addComponent()` rejects `Layer >= NUM_LAYERS` (20) with a log line, so
the foreground/bezel overlay declared at `layer="20"` in the wheel themes'
`layout.xml` does nothing. Either the bezel was intentionally disabled or it
is a quiet upstream bug. A maintainer with hardware should decide: move it to
layer 19 (it would then draw *over* the statusText at 19 — pick 18/19
deliberately) or delete the asset.

### K8. Auto-cover-art from gameplay snapshots (merges idea 21/N5)

Broader than N5's "favorites get a screenshot on exit": `Launcher::run()`
already executes `keymap rom '<path>'` before every launch, so recording the
currently running ROM is one line in the `keymap` script; then `snapshot`
(FN+UP, already wired to `fbgrab`) can *additionally* save
`<romdir>/<name>.png` when none exists — and `media.artwork_front` already
points at the ROM directory, so **playing a game once gives it cover art
forever**, filling the wheel by use. Needs the marker cleared on launch
return (the launcher scripts' post-`wait` tail) so menu screenshots taken
after exit aren't misattributed. Shell-only.

### K9. Per-system accent colour in the Favorites title strip

Once #43 exposes the owning system per item, tinting the bottom title strip
per system (a static system→colour map; the artwork generator already samples
per-theme palettes) makes the aggregate list scannable at a glance. Config /
art-pipeline only once the component type exists; not before.

### K10. `list.favoritesOrder = recent|alpha` knob

Favorites are forced alphabetical (`sortPlaylists()` follows "all"). Skipping
that sort for the aggregate's favorites playlist leaves them in
`favorites.txt` order — i.e. chronological, "recently starred first". Three
lines plus a config read; subsumes the cheap half of idea 17 (Star Log)
without changing the file format. Taste call: alpha is arguably better on a
240×240 screen; offer both.

### K11. Favorites count in the toggle acknowledgement

Same as item 6 (was M3, cheap half) — "Added to favorites — 12 total".
Recorded there; noted here only because the second review reached the same
spot independently. If #42 landed, the string flows through the OSD wrap
(30-col lines) — keep the sentence short.

## For future reviewers (context that keeps being useful)

- The five upstream patches (0001–0005) are small, individually commented with
  the *reasons* for each change, and the reasoning holds up: per-system
  `favorites.txt` as single source of truth is the right architecture; the
  skip-scan optimization is sound; the `title`-not-`fullTitle` marker decision
  avoids sort-jumps and file pollution deliberately.
- `pushCollection()` sets the menu to `&collection->items` and the follow-up
  `selectPlaylist("all")` replaces it with the playlist vector — so the
  favoritesOnly narrowing *does* take effect on entry; don't "fix" the
  one-frame discrepancy.
- `Page::cleanup()` runs on every menu-back (`RETROFE_BACK_MENU_ENTER`), which
  is what makes ownership-based freeing (#25) per-visit rather than per-exit.
- The `newItemSelected` flag on `ScrollingList` is write-only-sticky: set by
  every `Page::onNewItemSelected()`, never cleared (the Reloadable* classes
  clear only their own). So `allocateSpritePoints()`'s `if (old &&
  !newItemSelected)` is effectively never taken after first use, and every
  playlist switch / reallocate leaks the old slot components (their surfaces
  are already freed by `deallocateSpritePoints()`, so it's ~1 KB per event,
  not the bitmaps). #45 bypasses the path for toggles; S/O/V still hit it.
  Fix by always `delete old` and keeping only the baseViewInfo copy
  conditional — visuals unchanged.
- The kernel notification overlay (fbtft `notification` sysfs node) spec,
  verified against `DrUm78/linux v1.0-rg-nano`: 30 columns of 8×8 text on a
  black bar at the top of the screen; `^` or `\n` breaks lines; spaces center
  manually (volume OSD convention); writing `clear` retracts; composited
  continuously in `spi_async_mode`, so it appears even while the frontend is
  idle and over games; `notif set N` backgrounds a self-clearing process and
  pkill-coordinates with other notices. This is the right channel for *any*
  transient frontend feedback on device — #42 uses it for favorite toggles;
  prefer it over adding fixed-position text to 13 themes. (Direct C++ writes
  would bypass the pkill coordination — worst case a toast cleared early —
  which is why #42 shells out.)
- `importCurrentLayout()`'s missing-directory branch logs "Resetting Classic
  theme by default" but doesn't reset anything (falls through with the
  missing name), and `loadSplashPage()` calls `page->start()` on a possibly
  NULL page. With #28 the shipped config never reaches this, but a user
  deleting the active theme's directory still can. Upstream report material.
- During `RETROFE_HIGHLIGHT_ENTER`, only HIGHLIGHT/MENUJUMP results from
  `processUserInput()` are honored — a Y pressed inside a highlight animation
  (~0.25 s) is swallowed (no toggle, no feedback). Minor; queueing input
  across states is upstream's call.
- `controls.conf` `pageUp`/`pageDown` have no physical source on the RG Nano
  (no key emits PAGEUP/PAGEDOWN); harmless dead config. The Konami code
  (u u d d l r l r b a) *is* enterable on device and launches `bibi`.
- RetroRoomCovers, Daijismol, Artbook-sml and DarkUI ship byte-identical
  `layout.xml` files — edit all four or none.
- `controls.conf` is read only from the read-only rootfs
  (`absolutePath/controls.conf`); user copies on the share partition are
  ignored — there is no stale-user-config failure mode for new keys.
- The `zai-code-review.yml` GLM workflow only reviews same-repo branches;
  fork PRs get no automated review, by design.

# kimi.md — Starling (FunKey OS for RG Nano) review

A thorough source-level review of this repository (Starling 3.0.0, fork of
DrUm78/FunKey-OS `rg_nano`), with the five RetroFE patches applied to the pinned
upstream tag (`RetroFE-FunKey-1.1.4`) so the *actual shipped code* could be read
in context. All five patches apply cleanly.

Scope reviewed: the Favorites feature (patches 0001–0005 + collections + themes
+ artwork tool), the rootfs overlay (scripts, configs, themes), the Recovery
partition, the Makefile / genimage / swupdate config, the Docker build, and the
CI workflows.

Overall impression: the Favorites feature is thoughtfully done. Playlist
writes go to the FAT share partition (`$HOME/.retrofe` → `/mnt/FunKey/.retrofe`),
aggregation via `.sub` files keeps each system's `favorites.txt` the single
source of truth, the `collectionHasFavorites()` pre-filter avoids scanning
every ROM directory when opening Favorites, and the `Save()` rewrite
(mkdir -p, stream error checking, no stray `rootfsWritable()` calls) is
genuinely better than upstream. The CI hardening and release gating are
careful and well-documented. Findings below, roughly by category.

Legend for status: `[ ]` not started · `[~]` PR open · `[x]` done/merged · `[-]` won't do (rationale given).

---

## 1. Bugs

### B1. The "Added to favorites" statusText overlaps the game title in most themes — [~]
Patch 0005 added `<statusText x="center" y="224" xOrigin="center" yOrigin="center"
layer="19" alpha="1"/>` to all 13 layouts. In the default theme family
(RetroRoomCovers / Daijismol / Artbook-sml / DarkUI — these four ship the same
`layout.xml`), the selected-game title strip is
`y="bottom" yOrigin="center" yOffset="-17"` → text centered at y≈223, i.e. the
statusText is centered at *exactly* the same y. Text components do not clear
their background (`Text::draw()` only `renderCopy`s glyphs), so for 1.5 s the
two strings overdraw each other into an unreadable smear, at the very moment
the user is looking for confirmation.

Same story elsewhere: GameBoy (title at y≈223, fontSize 28), Classic and
Superlopez (y≈220), FunKey/FunKeyRed/FunKeyYellow (a text strip at y≈230).
TFT/Flat/PixxelPlus keep their titles higher up, so they collide less.

Fix implemented: route the message through the device's native toast instead —
the kernel notification overlay at `/sys/class/graphics/fb0/notification`, the
same mechanism `volume`, `brightness`, `snapshot`, `low_bat_check` and
`powerdown` all use (so it renders above any theme, and above RetroFE itself —
that already works today when you change volume while browsing). From C++:
write the message on `setStatusMessage()`, write `clear` when the existing
timer expires in `Page::update()`; no fork, no new component, no per-theme
tuning. Fall back to the layout `statusText` when the sysfs node is absent
(desktop/dev builds), so the 13 layout files stay valid.

### B2. Subcollection shells leak on every Favorites open (upstream leak, now on a hot path) — [~]
`RetroFE::getCollection()` builds one `CollectionInfo` per `.sub` file and never
frees it (the local `subcollections` vector in patch 0004 just drops the
pointers). Nothing else deletes them either (`grep` confirms no `delete` of
subcollections anywhere). Before Starling, `.sub` collections were essentially
unused on this device; Favorites makes the aggregate path run on *every* menu
visit. Each visit leaks, per favorited system: the `CollectionInfo`, its
`items` pointer vector (~8 bytes × ROM count — tens of KB for a big system),
and its playlist vectors. The `Item` objects themselves are *not* leaked (the
aggregate's destructor frees them), but the shells pile up: opening Favorites
20 times with favorites in a 5,000-ROM system leaks ~2 MB. The V3s has 64 MB
RAM total.

The shells can't just be deleted at the end of `getCollection()`: the
aggregate's items keep `Item::collectionInfo` pointing at them, and both
`Launcher::run()` and patch 0004's `favoritesOwner()` dereference that pointer
for the aggregate's whole lifetime.

Fix implemented: the aggregate takes ownership — a new
`CollectionInfo::addOwnedSubcollection()` stores the shell, and
`~CollectionInfo()` first clears each shell's `items` vector (so its destructor
doesn't double-free the shared `Item`s) and then deletes the shell, before
freeing its own items. `Item::~Item()` is trivial, so nothing dereferences the
shell during teardown.

### B3. `share`: multiple `.fwu` files silently disable recovery auto-update; the `.swu` loop is dead — [~]
`FunKey/board/funkey/rootfs-overlay/usr/local/sbin/share`:

- `[ -f /mnt/FunKey-*.fwu ]` — with two or more update files on the card, the
  glob expands to multiple arguments, `[` errors out ("binary operator
  expected"), the test reads as false, and the pending update is *silently
  skipped* at every boot. Exactly one file works; zero works. The README's own
  recovery instructions tell users to drop a `.fwu` on the card, and the
  Makefile comment notes the `FunKey-*.fwu` glob is load-bearing — so this
  edge is real.
- `for file in $(ls /mnt/FunKey-*.swu >/dev/null 2>&1)` — stdout is redirected
  to /dev/null *inside* the command substitution, so the loop body never runs.
  `.swu` updates have never been installed by this path. (Fixing it to
  actually install would *change* long-standing behavior on a device whose
  README says "early days", so the fix removes the dead loop with a comment
  rather than wiring it up.)

Fix implemented: iterate the glob like `S60recovery` does (handles 0/1/N
files), drop the dead loop with an explanatory comment.

### B4. Unfavoriting inside Favorites leaves the game on screen until you leave and re-enter — [x] resolved by #26 (other way)
In the aggregate page the displayed "all" playlist is a *narrowed copy* (patch
0004), so `removePlaylist()` erases the item from the favorites playlists but
not from the vector on screen. The marker is removed, the toast says "Removed
from favorites", but the game stays listed until re-entry. This is defensible
(the list doesn't jump under your finger; you can see what you just removed)
and it *is* consistent with the alternative reading (if you switch to the
"favorites" playlist view inside Favorites, the item does vanish). Keeping
as-is; documented here so the behavior is a decision, not an accident.

### B5. Y on the Main menu favorites a *system* — undocumented side effect — [x] resolved by #31 (other way)
`togglePlaylist()` doesn't distinguish leaf games from submenu entries, so
pressing Y on the Main menu adds e.g. "NES" to
`collections/Main/playlists/favorites.txt`, stars the system name, and makes
START (favPlaylist) on the Main menu filter to favorited systems. It works —
it's accidentally a "pin favorite systems" feature — but it's undocumented and
a stray Y press silently creates files. Decision: keep (it's coherent with
RetroFE's playlist model and harmless), but it's called out here; if it ever
surprises anyone, guarding `togglePlaylist()` on `selectedItem_->leaf` is a
two-line change.

### B6. Corrupt/missing `layout.conf` or deleted active theme → splash NULL deref / restart loop — [~]
`Configuration::importCurrentLayout()` only falls back to "Classic" when the
requested layout isn't in `layouts.list`. Two gaps:

1. `layout.conf` is a user-visible file on the FAT partition. If it's deleted,
   the fallback logic never runs and `settings.conf`'s `layout = FunKey Style`
   wins — a theme that **does not exist** in this image (upstream leftover).
2. If the layout directory itself is missing, the code logs "Resetting Classic
   theme by default" but doesn't actually reset (the assignment after the
   `stat` failure runs unconditionally).

Then `loadSplashPage()` calls `pb.buildPage()` and immediately `page->start()`
with no NULL check — a layout that fails to build crashes the frontend, and the
`frontend` script restarts it forever (black-screen boot loop needing Recovery).

Fix implemented (config-level, zero risk): point `settings.conf` at a theme
that exists (`layout = RetroRoomCovers`, matching the shipped `layout.conf`),
so the fallback chain always lands on a real theme. The missing NULL check and
the lying log message are upstream RetroFE issues — noted in §7 as upstream
suggestions rather than patched here (splash robustness is worth an upstream
report, not a fork patch that touches startup for every theme).

### B7. `Save()` writes `favorites.txt` non-atomically — [~]
`CollectionInfo::Save()` truncates and rewrites the playlist in place on the
FAT partition. This is a device that loses power by battery pull (the README
even documents the latched-state reset), and `instant_play` exists precisely
because power can die at any moment. A pull mid-write leaves a truncated
`favorites.txt` → favorites silently gone. Fix implemented: write
`favorites.txt.tmp` and `rename()` over the original (single directory-entry
swap on FAT), then the existing stream check confirms the rename target.

### B8. Non-fatal but real: `RetroFE.cpp` toggle/swallow during highlight animations
During `RETROFE_HIGHLIGHT_ENTER`, `processUserInput()` is called but only
`RETROFE_HIGHLIGHT_REQUEST`/`RETROFE_MENUJUMP_REQUEST` results are honored — a
Y pressed in that ~0.25 s window is swallowed (no toggle, no feedback). Minor
(mashers will just press again), listed for completeness. Not patched: fixing
it means queueing input across states, which is a behavior change upstream
should own.

---

## 2. General issues / hygiene

### G1. ~4.4 MB of cruft shipped on the read-only rootfs — [~]
- `layouts/*/splash_BAK.xml` (13 files), `layouts/FunKeyYellow/collections/*/system_artwork/device_BAK.png` (8 files),
  `layouts/Daijismol/collections/Atari lynx/system_artwork/bg.png.tmp`,
  `usr/games/collections/tmp.txt`, `layouts/Daijismol/collections/tmp.txt`,
  `usr/games/RetroFE.ico` (100 KB Windows icon; the Linux build never
  references it), `menu_resources/arrow_top_bak.png`, `zone_bg.bmp`.
- `usr/games/collections/CREATING_COLLECTIONS.txt` is upstream desktop
  boilerplate ("run RetroFE.exe -createcollection …") — meaningless on device.

Free to delete; nothing references them (checked against layouts and source).
Fix implemented in the same config-cleanup PR as B6.

### G2. `settings.conf` duplicates — [~]
`rememberMenu = true` *and* `rememberMenu = yes` both appear (later wins; same
meaning). `collections/Main/menu.txt` lacks a trailing newline. Folded into
the cleanup PR.

### G3. gmu (music player) is disabled but its package remains — [x] PR #30 re-enables it
Commit history shows gmu was first fixed to build against buildroot's
toolchain (`gmu.mk` sed rewrites), *then* disabled anyway (`# BR2_PACKAGE_GMU
is not set`, "Disable gmu so the OS can build"). Either the runtime was broken
or the disable was expedient. Options: re-enable it now that the build fix
exists (the RG Nano is a questionable music player, but upstream FunKey shipped
it), or delete the package directory so the tree doesn't carry a fixed-but-
unshipped app. Needs a maintainer decision / hardware test — not implemented.

### G4. `notif set` vs direct writes — coordination note — [ ] (accepted risk, documented)
The kernel-notification feedback (B1 fix) writes the sysfs node directly and
clears it when the timer expires. The shell `notif` command coordinates via
`pkill -f "notif display"`; direct C++ writes bypass that, so a C++-side
`clear` could end a volume OSD early (and vice versa). Worst case: a toast
disappears up to ~1 s early. Accepted; the same race exists between any two
shell `notif` users today.

---

## 3. Performance / stuttering

### P1. Toggling a favorite rebuilds the whole visible menu — [~]
The toggle routes through `RETROFE_PLAYLIST_REQUEST` → `playlistExit()` →
`onNewItemSelected()` → `reallocateMenuSpritePoints()`, which deallocates and
re-creates *every* visible wheel slot — each `allocateTexture()` is a chain of
`stat()`s over candidate artwork paths on FAT plus a PNG load+scale. ~5 slots
→ ~5 image decodes per Y press. No shipped theme defines `onPlaylistExit`/
`onPlaylistEnter` animations (checked), so there's no animation payoff — just
a ~100–300 ms hitch on a slow card, for a state change that affects one item.

Fix implemented: a targeted refresh. After a toggle, if the displayed playlist
still contains the selected item (the common case: adding from "all", or
toggling inside a system page), rebuild only the selected slot's texture
(`ScrollingList` gets a `reloadSelectedItemTexture()` mirroring
`allocateSpritePoints()`'s old-component handling) plus `onNewItemSelected()`
for the reloadable texts; skip the playlist round-trip. If the item *left* the
displayed playlist (unfavoriting while viewing "favorites"), keep the existing
full round-trip so the wheel re-lays-out correctly.

### P2. Opening Favorites rebuilds it from scratch every visit — [ ] (documented; not patched)
The 0005 pre-filter already skips systems with no `favorites.txt` (the big
win). What remains is: for each *favorited* system, a full ROM-dir scan +
`injectMetadata()` (sqlite `meta.db` lookup per game) on every single entry
into Favorites. With favorites spread over several big systems this is
hundreds of ms to seconds per visit. A proper fix is an aggregate cache keyed
on the `favorites.txt` mtimes — real surgery on RetroFE's load path, and the
payoff shrinks fast once P1 and B2 land (no more leak, no re-scan on toggle).
Documented as future work; the shape: keep the built aggregate on a side
cache, compare mtimes of the (already cheap to stat) playlist files, rebuild
only when one changed.

### P3. `CollectionInfo::sortPlaylists()` is O(|all| × |playlist|) per toggle — [ ] (fine, noted)
Called on every toggle via `addPlaylist()`/`removePlaylist()`. Even 10k ROMs ×
200 favorites is ~2M pointer compares — single-digit ms. Not worth changing;
noting so nobody "optimizes" it prematurely.

### P4. Everything else measured clean
- The per-frame `textStatusComponent_->setText()` (0005) is a cheap string
  store; `Text::draw()` renders from a pre-baked glyph atlas — no per-frame
  TTF rasterization.
- The render loop already skips rendering when idle (60 fps cap, event-driven
  `forceRender`) — battery-friendly.
- `collectionHasFavorites()` reads one small file per system per Favorites
  open — negligible.
- `Save()` on each toggle writes a few-KB file to FAT synchronously — fine.

---

## 4. Missing features

### M1. No persistent favorite indicator on box-art items — [ ] (idea, needs component work)
The `* ` marker (0005) only reaches *text* renderings: the selected-game title
strip and text-fallback lists. The wheel covers themselves carry no marker, so
in the default theme you can't see *which* games are favorites while browsing
— only the selected game's title shows `* `. Cleanest shape: a new
`reloadableText`/`reloadableImage` type (e.g. `type="isFavorite"`) that
renders a star glyph/icon when `Page::isFavorite()` is true for the selected
item — one small branch in `ReloadableScrollingText`/`ReloadableText` +
`ReloadableMedia`, then themes opt in with one line. Not implemented (touches
three component classes; better reviewed upstream-first).

### M2. Favorites list can't show which system each game belongs to — [~]
`type="collectionName"` renders `page.getCollectionName()` — so in Favorites
every game's status bar reads "Favorites". The item's real system is right
there (`selectedItem->collectionInfo->name`), and `Launcher` already relies on
it. Fix implemented: when the selected item's `collectionInfo` differs from
the page collection, show the item's owning collection instead. In ordinary
collections they are the same object → zero visible change; on menu pages the
items' `collectionInfo` is the menu collection itself → zero change; only the
aggregate gains the per-game system name. Applied to both `ReloadableText`
and `ReloadableScrollingText`.

### M3. No empty-state for Favorites — [~]
With no favorites anywhere, every `.sub` is skipped and Favorites opens onto a
blank page: background star, empty wheel, no explanation. First-contact users
*will* open it before favoriting anything. Fix implemented: when entering a
`favoritesOnly` collection whose item list is empty, push a hint through the
status/toast channel ("No favorites yet — press Y on a game", a few seconds).
Pairs naturally with B1's kernel toast (on device it appears as an OS toast;
on desktop as the layout statusText).

### M4. No "Recently played" / play tracking — [ ] (idea)
`instant_play` resumes the *last* game at boot, but there's no history. A
"Recently played" aggregate parallel to Favorites is conceptually adjacent:
launcher scripts already funnel through `launchers/*_launch.sh`; appending
`<system>:<rom>` with a timestamp to `/mnt/FunKey/.retrofe/recent.txt` is
shell-only. The RetroFE side (a second aggregate mode sorting by mtime, not
alphabetically) is the real work. High delight per effort; not implemented
(needs the RetroFE aggregation generalization).

### M5. No favorites management beyond toggling — [ ] (idea)
No way to clear a system's favorites on device, reorder them (order is forced
alphabetical by `sortPlaylists()`), or pick "most recently added first". A
`collections.Favorites.list.favoritesOrder = recent|alpha` knob is a
three-line change (skip the sort), but arguably worse UX than alpha on a
240×240 screen. Not implemented; noted as an option.

### M6. gmu — see G3.

---

## 5. Visual / layout issues

### V1. statusText/title collision — see B1 (fix routes around it entirely).

### V2. `foreground.png` in the wheel themes is declared `layer="20"` and is silently never drawn
`Page::addComponent()` rejects `Layer >= NUM_LAYERS` (20) with a log line, so
the foreground/bezel overlay in RetroRoomCovers & siblings does nothing. The
0005 comment documents the layer-19 reasoning but doesn't mention that the
theme's own layer-20 image is dead. Either intentional (the bezel looked bad)
or a quiet upstream bug. Not patched — changing it alters the shipped look;
flagged for a maintainer who can see the device.

### V3. Every Favorites entry carries the `* ` marker — [ ] (decided: keep)
Considered suppressing the marker inside the aggregate (all entries are
favorites by definition). Verdict: keep — the marker disappearing is the only
*persistent* in-list feedback that an unfavorite worked (B4 keeps the item on
screen), so the stars earn their place.

### V4. Theme art coverage for Favorites is complete and consistent — no action
Verified each theme's Favorites artwork matches the filenames its `layout.xml`
actually references (`device_W240` for the wheel family, `system` for
Classic/Superlopez, `logo` for Flat, `logo_h20` for TFT, `device_W140` for
FunKey*). `tools/gen-favorites-artwork.py` is well built (font fallback warns
loudly, palette sampling skips its own output on re-runs).

---

## 6. UX: making it friendlier, faster, more convenient

Implemented (see §1/§3): kernel-toast toggle feedback (B1), instant toggle
without menu rebuild (P1), empty-state hint (M3), per-game system name in
Favorites (M2).

Documented for later:
- **U1. Favorites count.** `type="collectionSize"` already exists; a
  per-collection layout override (`layouts/<theme>/collections/Favorites/layout.xml`)
  could show "12 GAMES" on the Favorites page — but it duplicates the whole
  layout file per theme, so it diverges from the base theme over time.
  Alternative: accept it on *all* pages (a count next to the collection name
  is nice everywhere). Maintainer taste call.
- **U2. Hide or annotate the Favorites entry when empty** (main-menu level).
  Requires rebuilding the Main menu per entry — more machinery than M3's hint
  for the same confusion. M3 chosen instead.
- **U3. Long-press Y for "favorite and stay" vs "favorite and advance"?**
  Over-engineering for two states; skip.
- **U4. Document the button map in README** — the Favorites README documents Y
  but not START = switch all/favorites playlist, L/R = letter jump, FN =
  random, MENU = on-device settings (incl. theme switch). One short section
  would surface features users currently can't discover. ~~Easy follow-up PR.~~
  Done by the concurrent session: #24.

---

## 7. Upstream (RetroFE-FunKey) issues found en route — worth reporting, not patching here
- `loadSplashPage()` NULL-derefs when the layout fails to build (B6).
- `importCurrentLayout()`'s "Resetting Classic" log on a missing layout
  directory doesn't reset anything.
- The Konami-code easter egg (`u u d d l r l r b a` → launches `bibi`) is
  reachable on device: D-pad + B + A. Delightful; keep.
- `Page::update()`'s old `setProperty("status", <empty>)` every frame (fixed
  by 0005) also *cleared the property every frame* — any other reader of
  "status" was starved. Worth an upstream note since 0005 only exists here.

---

## 8. Delightful / novel ideas (not implemented, sized)

- **D1. Auto-cover-art from gameplay screenshots.** `Launcher::run()` already
  runs `keymap rom '<path>'` before every launch, and `snapshot` (FN+UP)
  already grabs the framebuffer mid-game. If `keymap rom` recorded the ROM
  path and `snapshot` — when a game is running and the ROM has no
  `<name>.png` yet — also saved the grab as the game's `artwork_front`, then
  *playing a game once gives it cover art forever*. The wheel fills itself in.
  Shell-only, but needs care to not mis-attribute menu screenshots taken
  after exit (clear the marker on launch return). Medium.
- **D2. "Surprise me from favorites".** FN already jumps to a random game;
  scoping it to the current playlist (it may already — `selectRandom()` picks
  from the displayed list) means Favorites + FN = shuffle your greatest hits.
  Verify & document rather than build.
- **D3. A tiny star stamp on the Favorites tile when it has unseen additions**
  ("new since last visit") — needs a persisted snapshot of the previous
  favorite set. Small, cute, low value. Skip unless bored.
- **D4. Per-system star accent in Favorites** — tint the bottom title strip
  with the owning system's palette color (the artwork tool already samples
  per-theme palettes; a per-system color map is static config). Pure
  aesthetics, config-only once M2's per-item system is exposed to components.

---

## 9. CI / build / release notes (no action needed)
- `build.yml` ignores `**.md`/`docker/**` — so every rootfs or patch PR below
  triggers the full (hours-long) OS build. Expected; just don't batch-push.
- `release.yml` is dispatch-only and refuses non-`Starling-*` refs — good.
- `zai-code-review.yml` only reviews PRs **from the same repository**
  (`head.repo.full_name == github.repository`) — PRs from a fork get no GLM
  review by design. All PRs below come from a fork (no push access to
  `L-K-M`), so GLM will not fire on them; they'll be watched for human
  feedback instead.
- Docker path is coherent now (bookworm, builds this repo's `master`).

## 10. PR plan / status
Upstream default branch is `master` (there is no `main`). Midway through this
session two things happened: the account gained push access to `L-K-M`, and a
**concurrent GLM session** turned out to have done the same exercise — its
PRs (#24–#32, same-repo branches, GLM-reviewed) landed minutes before mine,
and it had already pushed its own `glm.md` + `ANALYSIS.md` to master.

I compared every pair and consolidated: duplicates closed in favor of the
better version (theirs, in all three cases), unique work kept and re-opened
from same-repo branches so the GLM review workflow runs on them.

| # | PR | Contents | Status |
|---|----|----------|--------|
| 1 | [#41](https://github.com/L-K-M/FunKey-OS-Starling/pull/41) | cruft removal, rememberMenu dedupe, menu.txt newline (G1, G2); layout fallback yielded to #28 | [~] open — GLM reviewed (0 actionable); both verification asks answered with evidence (first-wins proof, zero-reference grep) |
| 2 | [#42](https://github.com/L-K-M/FunKey-OS-Starling/pull/42) | patch 0020: kernel-toast toggle feedback (B1, G4) — unique to this set | [~] open — GLM reviewed 3×; all actionable points applied (apostrophe/caret stripping, toupper UB, padding underflow crash, system()-failure fallback, seconds≤0 gate, >30-col word splitting); remaining info points answered with driver/script evidence |
| 3 | — | empty-state hint (M3) | [-] closed (was #35): superseded by #27 (hint + fade) |
| 4 | [#43](https://github.com/L-K-M/FunKey-OS-Starling/pull/43) | patch 0021: per-item system name (M2) — unique | [~] open — GLM reviewed; its major was a false positive (menu items' collectionInfo is the menu collection itself, MenuParser.cpp:82,138); applied anyway as the leaf-guard + a shared Item::owningCollectionName helper (also fixes its duplication minor); re-review 0 actionable |
| 5 | — | subcollection leak (B2) | [-] closed (was #37): superseded by #25 (same design + fsync + set membership + null-safe save) |
| 6 | — | atomic save (B7) | [-] closed (was #38): superseded by #25's 0009 (adds fsync) |
| 7 | [#45](https://github.com/L-K-M/FunKey-OS-Starling/pull/45) | patch 0022: targeted texture rebuild on toggle (P1) — unique | [~] open — GLM review never landed: the Z.ai API timed out (300 s × 3 attempts) on five separate runs over ~2 h; retried each time. This is the "GLM times out" case; left open |
| 8 | [#44](https://github.com/L-K-M/FunKey-OS-Starling/pull/44) | share script: N-file `.fwu` fix, dead `.swu` loop (B3) — unique | [~] open — GLM reviewed twice; break-after-recovery_mode applied; .swu removal kept with evidence (the loop is verbatim-dead in both upstreams; nothing references .swu anywhere; a repaired loop would reinstall every boot) — respectful steady-state disagreement, maintainer's call |

Concurrent-session PRs covering findings from this review: #28 (B6 layout
fallback), #27 (M3 hint + fade), #25 (B2+B7 + more), #26 (B4, resolved the
other way: unfavorite removes from view), #31 (B5, resolved the other way:
leaf-guard), #24 (U4 README button map), #30 (G3 gmu re-enable), #29 (fast
patch CI), #32 (lowercase-sort cache). Review comments left on #25, #26, #27,
#31 — including one real bug found in #27 (the fade can leave short messages
drawn only at ~8% alpha on idle menus; fixes suggested), and the Item::leaf
evidence GLM asked for on #31 (constructor defaults true; only menu builders
set false).

Merge-order validation (all eleven pending RetroFE patches, buildroot filename
order, pinned tag): the concurrent series (0006-cache → 0009-power-loss-safe)
applies cleanly in alphabetical order and compiles. My kept patches (0020–0022)
apply cleanly on master but not over that series; rebases offered.

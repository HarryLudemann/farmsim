# Farm Sim — Milestone A + B (Flutter)

Working-title infrastructure/farm sim, per `../gamedesigndoc.md`. This is a
**Flutter** rewrite of the original SwiftUI prototype (kept in `../FarmSim/`
for reference) — same design, but developable entirely on Linux with no Mac
required day-to-day.

Implements Milestones A and B from §11:
- **A** — the by-hand loop: plant → water → grow → harvest → sell.
- **B** — the automated chain: Solar Panel → Wire → Pump → Pipe → Sprinkler,
  plus the Live/Manual toggle (§13), a full Shop menu (rather than a bottom
  tray) to browse/buy everything including tiered Wire/Pipe/Sprinkler, and
  Move/Demolish on placed buildings (§19–20).

Plus a full audit pass against every section of the doc (§1–27) for what
was already claimed as "done" — see **Audit findings** below for what that
turned up and fixed: a missing Silo capacity cap, the away-time catch-up
that §13 explicitly promises for Live Mode, a Silo interaction that skipped
the doc's own detail sheet, and the Status Bar badges from §23.

## Why Flutter, not SwiftUI

SwiftUI only builds on macOS — no way around that for the real thing. But
this game's rendering model is deliberately simple (§12: flat 2D shapes, no
physics, ticking every 4s), so SwiftUI's native performance edge buys
nothing here. Flutter's canvas/widget model fits "a grid of custom-drawn
shapes" well, and it gives real hot-reload directly on Linux — no cloud Mac,
no CI round-trip, just `flutter run`. A Mac (or free-tier CI) is only needed
for the final iOS build/App Store step.

## Audit findings (this pass)

Went through §1–27 checking what was already built against what the doc
actually says, rather than just adding new scope. Found and fixed:

- **Silo capacity was unbounded.** §18 specifies "50 units before it needs
  selling/emptying" — there was no cap at all. Deposits now stop at 50
  (`GameStore.siloCapacity`), covered by a test.
- **Live Mode's away-time catch-up didn't exist.** §13 says Live Mode
  "catches up on elapsed time on reopen ('while you were away…')", and §22
  spells out the mechanism (elapsed time → whole ticks, 12h cap) and the
  summary sheet. This is arguably central to what makes Live Mode's
  automation promise real rather than a slogan, and it was simply missing.
  Now implemented: on load, elapsed wall-clock time since the last save is
  converted to ticks (capped at 12h) and simulated before the UI even
  renders, then a "While you were away" sheet shows once. Tested end to
  end by backdating a saved timestamp and "relaunching" — including the
  detail that a hand-watered crop correctly does *not* progress (only
  Sprinkler-irrigated ones can, since by-hand actions can't happen
  retroactively).
- **Silo interaction skipped §19's own spec.** The doc's screen table says
  tapping a placed Silo opens a detail sheet — fill level, contents, a Sell
  button — not an instant sell-on-tap. Deposit (tapping while carrying a
  crop) rightly stays instant per §15's no-friction by-hand rule; an
  empty-handed tap now opens that sheet instead.
- **§23's Status Bar badges didn't exist.** Added both: a Silo-at-capacity
  badge and a "network genuinely in deficit" badge (wired-up but not
  actually getting power/water this tick — not just "not connected yet"),
  each tapping through to the relevant sheet.
- **Confirmed already correct:** the §2 connection rule (resource only
  reaches a tile if Pipe/Wire sits on *that* tile), Sprinkler's exact 3x3
  coverage math (§4/§5's worked example), the network supply/deficit rule
  applying per-component with no partial output (§18), by-hand delivery
  having no distance limit (§15) vs. automated delivery needing adjacency
  (§4) — these two are easy to conflate and weren't.
- **Confirmed as deliberate, not a bug:** the Lake blocking Wire/Pipe.
  §2's literal text only excludes Farmland from surface infrastructure —
  it's silent on the Lake. Given you explicitly want the Lake to never
  change, this is a product decision on top of an ambiguous doc, not a
  misreading of an explicit rule.
- **Newly noticed, not fixed (logged for later):** §4 says Elevated Ground
  "shades adjacent lower tiles" and Solar Panels produce "less output if
  shaded" — no shading model exists at all, Solar Panels always produce
  the flat 10/tick. Left alone for now since it's a real chunk of adjacency
  logic with no gameplay depending on it yet (no Wind Turbine to make
  Elevated Ground's other property matter either).

## What's here

- `lib/models/game_models.dart` — data shapes from §25, extended with
  `BuildingType.{solarPanel,pump,sprinkler}`, `GameMode` (§13), tiered
  `wireTier`/`pipeTier` ints (0 = none, 1 = basic, 2 = Heavy) in place of
  plain booleans, and per-tile `isPowered`/`isWatered` flags for the glow
  rendering in §12.
- `lib/engine/game_store.dart` — the tick engine:
  - By-hand rules (§15): Lake fills the watering can, Farmland
    plant/water/harvest, Silo deposit/sell.
  - **The Lake is immutable:** fixed terrain, and now enforced everywhere —
    no Wire, Pipe, or Building of any kind can be placed on it. (Buildings
    already excluded it via terrain validation; the Wire/Pipe path didn't,
    which was a real gap, now closed and covered by a test.) Every other
    non-Farmland tile stays freely buildable.
  - **Network resolution (§2, §10, §18):** every tick, flood-fills the Wire
    graph and the Pipe graph into connected components, sums each
    component's producer supply vs. consumer draw, and applies the doc's
    rule exactly — surplus is wasted, a deficit means *nobody* on that
    network runs this tick (no partial output). Solar Panels and Pumps
    inject into an *adjacent* Wire/Pipe tile (matching §4's wording); Pumps
    and Sprinklers *require* the resource on their own tile (§2's
    connection rule).
  - **Tiered infrastructure ("different levels" of Wire/Pipe):** the doc
    only specs tiers for Sprinklers (§4: 3x3→4x4→5x5, Tech-Tree-gated).
    Since there's no Tech Tree yet, tiers here are direct Shop purchases,
    and Wire/Pipe tiers are a deliberate extension in the spirit of §17's
    Efficiency branch ("cheaper-to-run Pumps... longer-range Solar
    Panels"): a **Heavy** Wire/Pipe tile boosts whatever Producer feeds
    through it by 50%, and cuts the draw of whatever Consumer sits on it by
    25%. Sprinkler's own two tiers are Base (3x3) and **Wide** (5x5) —
    consolidating the doc's Tier 2/3 into one upgrade for now, since the
    real Tier 2's off-center 4x4 needs its own direction-picker UI (§20)
    that isn't built yet.
  - Live/Manual mode (§13): a `Timer.periodic` in Live, an explicit
    `step()` in Manual — both call the identical tick function.
  - Placement (§19–20): cost/description table in `kPlacementInfo` (costs
    aren't specified in the doc — invented to keep an early "sell a few
    crops before automating" pace), terrain/adjacency validation per
    building, Demolish (50% refund) and Move (free replacement) on
    non-Silo buildings. Wire/Pipe use a streamlined tap-to-toggle instead
    of a separate demolish flow: tapping an already-placed tile removes
    *whatever tier is actually there* (not necessarily what's currently
    selected in the Shop) and refunds 50% of that tier's cost.
- `lib/widgets/` — flat shape rendering (§12), no image assets, plus the
  idle "juice" the doc explicitly calls for: a shared animation clock
  drives crop sway, a Lake shimmer streak, and a Solar Panel highlight
  sweep. Wire/Pipe presence shows as small corner glyphs that light up
  (amber/blue) when that tile is actually carrying power/water this tick,
  with a small amber chip marking Heavy tiles regardless of state.
- `lib/widgets/shop_sheet.dart` — the **Shop**: a full-screen draggable menu
  (not a bottom tray) grouped into Infrastructure/Producers/Automation
  sections, showing every item's icon, tier badge, description, and cost
  (cost renders red when unaffordable, per §23's "invite, don't gate" copy
  principle). Tapping an item arms it and closes the sheet.
- `lib/widgets/placement_banner.dart` — replaces the Tray's old
  show-what's-selected role: a small pill above the grid while something's
  armed, with a Cancel (§20's "small X near the Status Bar").
- `lib/widgets/building_info_sheet.dart` — the Building info bottom sheet
  (§19–20) with Move/Demolish, now tier-aware (shows Sprinkler's actual
  coverage and whether it's sitting on a Heavy tile).
- `lib/widgets/silo_detail_sheet.dart` — §19's Silo detail sheet: fill
  level, contents, and a Sell button. Opens on an empty-handed tap; a
  carried-crop tap still deposits instantly per §15.
- `lib/widgets/away_summary_sheet.dart` — §19/§22's "While you were away"
  sheet, auto-presented once after a Live-mode catch-up actually simulated
  missed ticks.
- Status Bar badges (§23) in `status_bar_view.dart` — a full-Silo badge and
  a network-deficit badge, each tapping through to the relevant sheet.
- `test/widget_test.dart` — 11 tests: the by-hand loop end-to-end, the full
  automated chain via the real placement API (zero manual watering taps),
  Live/Manual switching, placement validation, Lake immutability across
  every placeable type, Heavy Wire/Pipe's boost/reduction actually changing
  tick outcomes, the Shop sheet arming a selection, Silo capacity, the
  Status Bar badges appearing/clearing, and away-time catch-up (verified by
  backdating a save and "relaunching"). Run these instead of trusting a
  visual read alone — several real bugs (a layout overflow from a
  selection border, a grid-sizing bug that ignored available height) were
  only caught this way.
- 6×6 fixed grid, one crop (wheat), one pre-placed Silo, portrait iPhone
  layout.

## What's deliberately NOT here yet

- Mines/Factories/Ore, Deep Pipes, Hubs, Batteries, day/night (§4, §7–9) —
  explicitly "after Milestone B" per §11's own roadmap.
- Auto-Seeder, Auto-Harvester, Auto-Seller, Fertilizer Spreader (§16) — the
  rest of the Automation Stack beyond Sprinkler; doc's own suggested next
  unlock is Auto-Harvester.
- Tech Tree and Decorations (§17) — no currency sink yet beyond buildings.
- Solar/shading model (§4: Elevated Ground shades neighbors, Solar Panels
  produce less when shaded) — noted in the audit above, not built.
- A second crop type, multiple Silos, grid expansion (§7, §11).
- Onboarding/coach-marks (§21), Settings screen (§24).
- Real chime SFX (§1 mentions "satisfying chimes") — only haptic feedback
  (`HapticFeedback`) on sell/placement for now; no audio assets sourced yet.
- Firebase (§22, §27) — saves are local (`shared_preferences`) only, so this
  does **not** yet meet the doc's "always-online, cross-device" bar. That
  needs a Firebase project and bundle ID only you can create — say the word
  when ready and we'll wire it in (`firebase_core` + `cloud_firestore` +
  `firebase_auth` map directly onto §27's structure).

## Running it (Linux, no Mac needed)

Flutter is already installed via `mise` (same tool managing your other CLIs)
— it's just available as `flutter` in any new terminal.

```bash
cd /home/harry/Work/farm-sim/farmsim
flutter pub get

# Live-reload in Chromium (works out of the box, no extra system packages):
CHROME_EXECUTABLE=/usr/bin/chromium flutter run -d chrome

# Run the automated tests (the real check that the game logic works):
flutter test
```

Press `r` in the running `flutter run` session for hot reload, `R` for hot
restart, `q` to quit.

### Optional: native Linux window instead of a browser tab

This needs two small system packages that require `sudo` (which I can't run
myself) — one-time setup:

```bash
sudo pacman -S cmake ninja
flutter run -d linux
```

## Shipping to an actual iPhone later

You do not need to own a Mac for this:
- **Free-tier CI (recommended when you're ready):** Codemagic or GitHub
  Actions macOS runners can run `flutter build ipa` in the cloud on a
  macOS image, output a build, and (with your Apple ID configured) upload to
  TestFlight — you drive it all from Linux via git push.
- **Occasional cloud Mac rental** (MacinCloud, Scaleway Mac mini) if you
  want to poke at things in real Xcode/Simulator directly.

## Try it

**By hand (§15):**
- Tap either Lake tile to fill the watering can (blue tiles, row 2).
- Tap an empty Farmland tile (brown, row 4) to plant wheat.
- Tap a planted tile with a charge available to water it — grows one tick
  (4s) per successful watering, ready after 6.
- Tap a ready (glowing gold) crop to pick it up; tap the Silo while
  carrying to deposit instantly. Tap the Silo empty-handed to open its
  detail sheet (fill level, contents) and sell from there.

**Automated chain (§4, Milestone B), using the Shop (storefront icon in the
status bar):**
1. Open the Shop, tap Solar Panel (40c) — the sheet closes and it's armed;
   tap open ground to place it.
2. Open the Shop again, tap Wire (2c) — Wire (and Pipe) stay armed after
   placing so you can lay a chain by tapping several tiles in a row toward
   the Lake. The banner above the grid shows what's armed, with a Cancel X.
3. Pump (30c): place it on a tile adjacent to the Lake *and* sitting on
   your Wire chain (it needs power on its own tile). Consider Heavy Wire
   (8c) instead of a stretch of Basic — it boosts a Solar Panel feeding
   through it by 50%, or cuts a Pump's own draw by 25% if placed under one.
4. Pipe (2c) or Heavy Pipe (8c): extend a chain from next to the Pump
   toward your Farmland.
5. Sprinkler (25c, 3x3) or Sprinkler Wide (55c, 5x5): place on a tile
   bordering Farmland, sitting on the Pipe. Watch its coverage tiles water
   themselves — no more taps.
6. Tap any placed Solar Panel/Pump/Sprinkler (outside placement mode) to see
   its live connection status — including whether it's benefiting from a
   Heavy tile — and Move/Demolish it.
7. The play/pause icon in the status bar toggles Live vs. Manual (§13); in
   Manual, a Step button appears to advance one tick at a time.
8. Try tapping a Lake tile while anything is armed — it always comes back
   invalid (red flash). The Lake never changes; everything else can.
9. Fill a Silo to 50 and it stops accepting deposits — a badge appears in
   the status bar; tap it to jump straight to the Silo's detail sheet.
10. Close the tab and reopen it (or hot-restart) after your Sprinkler chain
    has been running a minute — you'll get a "While you were away" summary
    on load, and the crop under your Sprinkler will have kept growing the
    whole time.

## Next steps, in the order the design doc suggests (§11, §16)

1. Play-test both loops (`flutter run -d chrome`), tune anything that feels
   off — building costs especially, since the doc doesn't specify them.
2. Auto-Harvester next (§16's own suggested unlock order after Sprinkler),
   then Auto-Seller, Auto-Seeder, Fertilizer Spreader.
3. Second crop type + Silo, then Mines/Factories/Ore, Deep Pipes, Hubs,
   day/night + Battery (§7–9) — all explicitly "after Milestone B" in §11.
4. Tech Tree and Decorations (§17) once there's a reason to sink surplus
   coins/tools somewhere.
5. Decide when to wire up Firebase (§22/§27) — needs your own Firebase
   project/credentials, so it's a good point to loop back in.
6. When ready to actually ship, set up Codemagic/GitHub Actions macOS CI for
   the iOS build step.

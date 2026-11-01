# Touch Frogert — Arcade V2: Research Findings & Implementation Plan

Status: **APPROVED by owner.** Decisions: keep ROM ZIPs in repo (no history rewrite), package `com.mundymorningstudios.touchfrogert`, name "Touch Frogert".
Branch: `feature/frogert-arcade-v2` · Starting commit: `236d648` (`main` at `2160160` plus two "Touch Developer push" commits that added only the two ROM ZIPs).

The ROMs were used only as observation references (MAME 0.264, both sets verified "good"). Nothing was extracted, disassembled
for reuse, or copied. This document records general principles and measured *behaviour*, not code, graphics, or sound.

## 0. URGENT repo-hygiene findings (need your decision)

1. **The two ROM ZIPs are committed to a *public* repository** (`qbert 2.zip`, `frogger (1).zip`). That is redistribution of copyrighted
   ROMs, and they are now in git history. Recommend: remove them from the branch and purge history (needs a force-push / history rewrite,
   which I will NOT do without your explicit permission), and keep research ROMs out of the repo (local only).
2. **Export guard.** (Update: testing showed Godot's `all_resources` mode does not export non-resource files such as `.zip`, so they were not
   being packed. Exclusions were added anyway as defence in depth; see `tools/verify_no_rom_content.py`, which CI runs on the real APK.)
   Original concern: `export_presets.cfg` had an empty `exclude_filter`. Fix before any further build: `exclude_filter="*.zip,research/*,docs/*,tools/*"` and add
   `*.zip`, `*.bin`, `*.rom` to `.gitignore`. (Every push currently triggers an APK build, so this applies to the very next push.)
3. I have not deleted anything. The ZIPs remain in place until you say so.

## 1. Existing project (what we have)

- Godot 4.3, GL Compatibility, portrait 720x1280. Working CI: `build-android.yml` builds a signed-debug arm64 APK on every push
  (debug keystore generated at build time) and uploads artifact `Touch-Frogert-debug`. **Keep this as-is.**
- Game is "Neon Hopper": one 1,100-line `main.gd` drawing everything via `_draw()`; 7-row isometric pyramid, tile-claiming (the thing V2
  explicitly drops), tongue/cheek/fly prototype, procedural-WAV SFX, hi-score save, headless `--autotest` bot, swipe/tap input.
- Reusable: deterministic fixed-step loop (`step(dt)`), procedural audio synth (`make_tone`/`make_seq`), pyramid projection math,
  tongue/fly/cheek idea, autotest harness, CI. Not reusable as-is: monolithic script, tile-claim rules, tap-quadrant input.
- Package id `com.mrmundysr.neonhopper` / name "Neon Hopper" must be renamed to Frogert (decision needed: changing id breaks upgrades — fine pre-release).

## 2. Research method

MAME 0.264 under xvfb, Lua harness (`tools/research/mame_play_harness.lua`) inserts a coin, starts, plays random inputs, records AVI and
logs object RAM; `frogger_row_speed.py` derives conveyor behaviour from the scroll registers. Q*bert RAM was not logged (observation of video only), so
Q*bert timing numbers below are qualitative; I can add RAM logging if you want hard numbers.

## 3. What the classics teach

### Frogger (observed)
- **Lanes are independent clocks.** From the scroll registers: every lane moves in *discrete steps*, each lane at its own cadence
  (measured step rates per lane ranged from ~13% to ~38% of frames; one lane stepped 2x farther per tick). **Directions alternate lane to lane.**
  Result: simple rules, rich emergent patterns — gaps line up and drift apart on different periods, so players learn *rhythms*, not sequences.
- **Two zones, two verbs.** Road = avoid (lethal on touch); river = *must* ride (lethal on the gap). Same movement, opposite risk —
  a safe median strip in the middle gives a breather and a decision point.
- **Carry rule:** riding a log moves you with it; leaving the screen edge kills. The frog's hop is discrete (one cell, committed), so
  every move is a readable commitment.
- **Pacing/economy (on-screen text):** 3 frogs, 10 pts/step, 50/frog home, 1000 for filling all five homes, +10/remaining second, one extra
  frog at 20,000. A visible timer bar forces forward motion (anti-camping). Five home slots with occasional hazards (fly bonus, lurking
  predator) punish lazy aiming at the goal.
- **Difficulty:** same board, rising speeds/densities, extra hazards; the screen is always instantly readable.
- **Attract:** cycles title, point table, ranking, and a *real played demo*, with "insert coin" — teaches rules without text walls.

### Q*bert (observed)
- **Diagonal-only isometric hop**: 7-row/28-cube pyramid; one input = one committed hop; falling off edge = death — "geometry is the enemy".
  Edge risk and enemy approach are what create tension; there are no walls to corner you, only the void.
- **Escape valve:** spinning discs on the sides are one-use lifelines — teaches routing and rewards memorised planning.
- **Enemy roster is small but each has one clear rule** (ball that falls down; egg→chaser that hunts by your position; sideways wrong-way pests;
  colour-reverters). Distinct silhouettes/behaviours = readable at a glance.
- **Round/level structure:** same pyramid, new objective rules per level (extra hops per cube, reversion), so repetition stays fresh while
  skills transfer. Scoring is tiny and frequent (feedback every hop).
- **Feel:** hop is fast with a clear arc and a short landing, input buffered so chains feel fluid; a death has a short dramatic beat (speech bubble)
  then immediate restart, so retry cost is ~2 seconds.
- **Attract:** instruction pages, high-score table (3-initial), and a self-playing demo cycle.

### Principles we adopt (in our own words)
1. One input = one committed, readable action; short lockout, buffered next input.
2. Lanes as independent deterministic clocks with alternating direction; patterns learnable by watching.
3. Every hazard has *one* rule and a distinct silhouette. Water is never destroyable (per your spec) so it stays a constant puzzle.
4. Retry cost ≈ 2 s; identical restart (seeded) so failure feels like the player's, not RNG's.
5. Pressure (narrowing pyramid, timer/fly-hold fuse) prevents camping while safe zones (wide bottom rows) allow planning.
6. Frequent micro-rewards and a visible risk/reward lever (hold the fly longer = more power, closer to exploding).
7. Constraints made the originals great: few sprites, flat colours, tiny rule sets, big readable shapes — good for budget Android too.

## 4. Specification risks / contradictions (please rule on each)

1. **Movement geometry on a narrowing pyramid.** "Rows move sideways" + "pyramid isometric hop" conflict: on a diagonal grid a moving row
   shifts cells so a diagonal hop's target changes under you. Proposal: rows are *lanes of cells*; hop up = to the cell in the next lane
   whose span overlaps most with your cell *at hop-landing time* (up-left/up-right selected by swipe), with a fixed hop duration (~0.18 s) so the
   landing target is predicted. Needs your sign-off or a prototype review.
2. **"Carried beyond pyramid boundary costs a life" vs narrowing summit:** upper rows are shorter, so conveyors there are shorter loops and
   faster *in apparent* terms — need a speed-per-cell-length rule to keep fairness (parameterised in tuning panel).
3. **Fly rules:** touching a ripe fly kills, yet flies "travel with the row" and sit in the lane space you'd land on. Need a guaranteed
   landing-alternative / telegraph (fly growth stages visible) — implement as fairness constraint in level generator.
4. **Float vs shoot:** shooting while floating sinks you. That's a clear trap; add a distinct pre-shot cue (and an A-button "are you sure" tell, e.g. cheek wobble) to keep it fair.
5. **Two lives-extra sources** ("score and occasional rewards"): define exactly (proposal: extra life at 10k then every 25k; reward fly worth +1 life rare, max 5 lives).
6. **Destroyable barriers "for the remainder of the attempt" vs "restore on death"** — consistent, but note intermission/level restart must reset; plain.
7. **Controls:** B-hold aiming plus swipe means swipe has two meanings; second thumb needed — OK with invisible regions but
   default layout must keep A/B reachable without covering swipe area. Android edge-gesture conflicts (immersive mode) must be tested.
8. **"Authentic ... original movement geometry"** while forbidding copying presentation: we keep *mechanics* (hop-on-pyramid) but must differentiate visually
   (design pass: no orange hairy hero, no cube colour scheme, no rainbow discs, no sound-alikes). Also check name/trade dress: "Frogert" is distinct; keep it.
9. **Fly hold fuse timing** (stages, explode time) is unspecified: proposed stages 0–2.5 s green/yellow, 2.5–5 s orange, 5–7 s red, pop at 7 s (all tunable).
10. **"Bots test skilled and imperfect play" in Godot headless** — needs the sim split from rendering (see plan) or bots will be slow/unfaithful.
11. **Music/SFX** must be authored from scratch (procedural synth is fine; no sound-alike melodies).

## 5. Implementation plan

**Architecture** (Godot 4.3, GDScript, `_draw`/Sprite2D hybrid, no per-frame allocations):
- `sim/` pure-logic, no nodes: `Board` (pyramid lanes), `Lane` (clock, direction, items, wrap), `Frog`, `FlyState`, `Projectile`, `Rules` — fixed 60 Hz step, seeded RNG, serialisable state → deterministic replay & headless bots.
- `gen/LevelGen.gd` rule-based generator (seed, level, params; fairness validator rejects unwinnable layouts, e.g. min safe-crossing windows per lane).
- `view/` rendering + original vector-style sprites for frog (4 facings, mouth direction, cheek inflate stages), Miss Frogert, lily pads, barriers, flies (growth), water; animation via code/atlas.
- `arcade/` reusable **TouchArcade controller** (autoload/module): invisible regions, multi-touch tracked by touch index, swipe recogniser, hold/combo actions (action map JSON), setup/test screen (drag, resize, handedness, defaults, test), config saved to `user://`.
- `ui/` attract mode (replays recorded deterministic demo inputs through the real sim), title, 3-initial hi-score, leaderboards (score + highest level), intermissions every N levels (scripted cartoon, original art), victory animation.
- `audio/` procedural music + SFX synth (reuse existing synth), mixer, haptics optional.
- `dev/` debug panel (only in debug builds / hidden gesture): lane speeds, difficulty params, presets save/load (JSON), jump to level, identical restart, row numbers top→down, event log (deaths, positions, timing) to `user://logs` + on-screen.
- **Bots** (`tools/bots/`): `--bot=skilled|sloppy|random`, run N seeds per level headless, output completion rate, median time, death-cause histogram, unreachable/impossible-config flags; run in CI as a gate.

**Milestones (each = one reviewable push, CI APK each time):**
- M0 hygiene: ZIP removal decision, export excludes, rename package/app, folder scaffolding, keep CI green.
- M1 sim core + lanes + hop + carry + death/restart, bare-shape rendering; bot harness v0. *Prototype review checkpoint on hop geometry (risk #1).*
- M2 TouchArcade controller + setup screen.
- M3 flies/tongue/cheek/projectile/barriers/water rules; sprites with 4 facings.
- M4 level generator + dev panel + logging; you tune levels 1–2; bots extrapolate progression.
- M5 game flow: lives/scoring/extra lives, victory, intermissions, hi-score entry, attract demo.
- M6 audio, polish, perf pass on budget devices (target 60 fps on ~2 GB RAM/Mali-G52 class; atlas, no allocations in step, ≤ ~150 draw items), balance via bots.
- M7 release candidate APK via GitHub Actions (debug now; release signing only with your approval/secrets set up by you).

**Android delivery:** keep current workflow (builds on push, artifact `Touch-Frogert-debug`); add a Godot `--headless` bot-test job before export; add APK size check and verify no `*.zip/*.rom/research` in the PCK.

## 6. Decisions I need from you
1. Remove the ROM ZIPs from the repo (and purge history)? 
2. Approve the hop-geometry proposal (risk #1) or request a different model.
3. Rename package id/app name now?
4. Confirm the numbers in risks #5 and #9 as starting defaults.
5. Approve the plan so I can start M0/M1.

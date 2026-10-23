# SKOUTAR – Game Logs / Pitch Profiles / Pitch Sequencing fixes

Made against `haydenwildman/skoutar`, branch `main`, commit `900cd37` ("Rebuild SKOUTAR with Supabase key").
Nothing was committed or pushed. No Supabase credentials, auth, database or config files were touched.

## IMPORTANT: what was and was not verified
- I could read and clone the repo, but my environment has **no Dart or Flutter SDK** (and cannot download one).
- So `dart format`, `flutter analyze` and `flutter test` were **NOT run**. Nothing here has been compiled.
- What I did check: every edited file has balanced brackets, and `skoutar_changes.patch` applies cleanly (`git apply --check`) to a fresh clone of `main`.
- Please run the commands in step 4 below before trusting any of it. If analyze or a test fails, send me the exact output and I will fix it.

## What changed

### Fix 1 – Pitch Breakdown > Pitch Profiles > Approach  (`lib/screens/pitch_breakdown_screen.dart`)
- The separate **Usage %** column is gone from the Approach view (it now shows Take %, Swing %, Whiff %, Foul %).
- Each pitch row's label cell now shows the pitch name and its usage % together (for example `FB` over `40.9%`), above the pitch-count pill.
- The value is the existing `usagePct` from `StatsService.pitchBreakdown` (pitches of that type / total pitches in the current filter). Nothing is hardcoded.
- The label cell is shared by all three views, so usage also shows in Results and Contact. The OVERALL row keeps only its total pitch count.
- Phone label column widened from 56 to 62 px so the percentage fits.
- Untouched: the summary cards, the Usage % bar chart above the table, the press-and-hold info (it now also explains Usage).

### Fix 2 – Game Logs line charts  (`lib/screens/game_logs_screen.dart`)
- Actual cause: each chart reserved a fixed 76 px per game and sat inside a horizontal `SingleChildScrollView`, so every added game made it wider.
- Now each chart fills exactly the width of its card and the games share that width. No horizontal scrolling.
- They are still the same three line charts, same data, same dot colors, same tooltips. No games or points are dropped.
- When games get crowded: opponent labels are thinned (every Nth, always including the newest game) and dots shrink slightly. Tap or hover any dot to see its game.
- Note: the third chart in your repo is titled **"K% by Game"**, not "Ks by Game". I kept the existing chart and title.

### Fix 3 – Game Logs  (`lib/screens/game_logs_screen.dart`)
- Removed the "Count & Approach Snapshot" card. Nothing was left behind in the layout.
- `StatsService.countApproach` / `groupedCountStats` are untouched; the Count & Approach tab and Scouting Report still use them.

### Fix 4 – Pitch Sequencing "not enough data"
Files: `lib/services/sequence_scoring.dart`, new `lib/services/sequence_analytics.dart`, new `lib/widgets/sequence_analytics_view.dart`, `lib/screens/pitch_sequencing_screen.dart`.

**Cause.** I cannot see your Supabase data, so I could not observe it failing. What the code shows:
1. The whole screen was replaced by "Not enough data yet" whenever the one scored-sequence list (finished at-bats with 3+ pitches) was empty. That hid every other metric.
2. Plate appearances were rebuilt by walking rows in reload order and cutting a new at-bat whenever the stored `batter` number changed between neighbouring rows. Rows are reloaded sorted by `ts`, then random `id`. Rows from **Add Row / Insert Row Above** in Edit Raw Data get a new timestamp (and `paId` 0), and bulk-created rows can share a timestamp. Those come back out of order, and the at-bats get cut into 1-2 pitch fragments that can never form a 3-pitch sequence. Counts like ERA/WHIP do not depend on order, which fits only sequencing breaking.
This is the most likely mechanism, not a confirmed diagnosis for your database. The new "Data used" card at the top of the screen shows pitches, plate appearances, finished, finished with 2+ and 3+ pitches, so you can see immediately what your data contains.

**Fix.**
- `splitPlateAppearances` now groups by game and stored batter sequence number and orders by stored pitch number, so reload order no longer matters. An at-bat ends at the first pitch with an outcome. Rows with `call == 'dk'` are still not pitches.
- The screen is never replaced by one message. New sections each show on their own and say exactly what is missing when they cannot be calculated: Data used, Sequence effectiveness (first 2 or first 3 pitches), Results after each pitch type, Pitch-to-pitch transitions, Performance by count (with pitch mix per count), Pitch selection by count situation (first pitch / ahead / even / behind / two strikes), and By batter handedness (only when both hands have pitches).
- All numbers are plain ratios of stored rows with sample sizes (n) and a small-sample flag. The only modeled number is the Wilson 95% lower bound on Out% used to rank opening sequences (no hand-picked weights). The old 0-100 Decision Score lists remain below and are now labelled as modeled.
- Missing optional fields do not discard pitches (missing pitch type is grouped as OTHER; missing call counts as neither strike nor ball). Sequences never cross game or at-bat boundaries.
- A dropped third strike (`dk3`) counts as a strikeout but not as an out by itself in the new tables.
- Caveat: the app stores batter hand `R` when none was chosen, so a split with very few L pitches is thin data.
- Existing at-bat review, put-away pitch, first-pitch strike, and Count Tendencies are unchanged.

### Tests (not run)
- New `test/sequence_analytics_test.dart`: shuffled rows, inserted row with a newer timestamp, identical timestamps, dropped third strike, 2-pitch-only data, transitions, counts, count situations and mix, hand split, empty input.
- `test/pitch_profiles_test.dart`: the Approach header test now expects Take/Swing/Whiff/Foul % and **no** Usage % header, plus usage % shown.

## Files in this ZIP
`files/` holds complete replacement files at the same paths as your project, plus `skoutar_changes.patch` (the same changes as one unified diff).

## Apply to `C:\SKOUTAR\SKOUTAR` (PowerShell)
1. Extract the ZIP somewhere else, e.g. `C:\SKOUTAR_fixes`, and review it.
2. Safety copy: `git -C C:\SKOUTAR\SKOUTAR stash -u` if you have uncommitted work, or copy the folder.
3. Either copy the files:
   `Copy-Item -Recurse -Force C:\SKOUTAR_fixes\files\* C:\SKOUTAR\SKOUTAR\`
   (only if your local copies of those 8 files match `main` @ 900cd37; otherwise use the patch)
   or use the patch from the project root:
   `git apply --check C:\SKOUTAR_fixes\skoutar_changes.patch` then `git apply C:\SKOUTAR_fixes\skoutar_changes.patch`
   If it fails, `git apply --3way ...` or send me the failing file.
4. Test:
   `cd C:\SKOUTAR\SKOUTAR`
   `dart format lib test`
   `flutter analyze`
   `flutter test test/sequence_analytics_test.dart test/pitch_profiles_test.dart test/sequence_scoring_test.dart`
   `flutter test`
   `flutter run -d windows`
5. Check by eye: Pitch Breakdown > Approach (no Usage column, % beside pitch names); Game Logs (add games or narrow the window, no sideways scroll, no Approach Snapshot); Pitch Sequencing (open "Data used", then each section).

## Also in your repo
`01-…`, `02a-…`, `03a-…` `.patch` files from an earlier round are committed in the repo root but were not applied to `lib/`. I reused only the sequencing ideas from 01/02a/03c (reviewed, then extended and corrected, for example `dk3` instead of `kdk`). I did not use the Game Logs patch (04) or 03a/03b/02b.

## Known limitations
- Not compiled, formatted, analyzed or tested (see top).
- Fix 4's root cause is inferred from code, not observed in your data.
- Chart label thinning and dot sizes were chosen by calculation, not by looking at the rendered chart.

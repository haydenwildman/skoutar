# SKOUTAR patches (made against github.com/haydenwildman/skoutar main @ 933f06b)

Seven independent patches. Each one was verified to apply to that commit on its own, and all seven
together reproduce the intended files. NOT compiled or tested (no Flutter in my environment).

Run from the project root (C:\SKOUTAR\SKOUTAR). Commit/stash your own work first so you can undo.

## 1. Check each patch separately (changes nothing)
PowerShell:
    Get-ChildItem *.patch | Sort-Object Name | ForEach-Object { git apply --check $_.FullName; "$($_.Name): exit $LASTEXITCODE" }
(Copy the .patch files into the project root, or give full paths.)

## 2. Apply
    git apply 01-new-files.patch            # always safe: only adds new files
    git apply 02a-sequence-scoring-pa-rebuild.patch   # THE ROOT-CAUSE FIX, needed
    git apply 02b-sequence-scoring-kdk.patch          # skip if it fails: you likely already have 'kdk' in resultValue
    git apply 03a-sequencing-screen-remove-usage-pct.patch   # skip if it fails: USE% already removed
    git apply 03b-sequencing-screen-no-horizontal-scroll.patch
    git apply 03c-sequencing-screen-wire-analytics.patch     # needed: shows the new sections
    git apply 04-game-logs-and-stats.patch

If one fails, try  git apply --3way <file>  (merges against your history), or
git apply --reject <file> (applies what it can, leaves .rej files). Send me the failing hunk or the
current file and I will adapt it. Do not skip 01, 02a, 03c: the new screen sections depend on them.

## 3. Test
    dart format lib test
    flutter analyze
    flutter test test/sequence_analytics_test.dart test/sequence_scoring_test.dart test/stats_logic_test.dart
    flutter test
    flutter run -d windows
Then: Pitch Sequencing (open "Data used": pitches -> plate appearances -> finished -> 3+ pitches),
Game Logs (resize the window narrow and wide; charts must never scroll sideways).

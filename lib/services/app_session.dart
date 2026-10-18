import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/pitcher.dart';
import '../models/user.dart';
import '../models/pitch_event.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';
import 'pitcher_service.dart';
import 'storage_service.dart';

/// ══════════════════════════════════════════════════════════════
/// APP SESSION
///
/// The single source of truth for "who is logged in" and "what pitch
/// data is loaded" — this is the Flutter equivalent of the R Shiny
/// `server()` function's `reactiveVal`/`reactiveValues` (logged_in_user,
/// raw_data, gs$balls/strikes/outs/pitch_num, lineup, etc).
///
/// Screens listen to this via `context.watch<AppSession>()` /
/// `Provider.of<AppSession>(context)`.
/// ══════════════════════════════════════════════════════════════
/// Returned by [AppSession.addPitch] so the UI knows whether the at-bat
/// just ended, and if so, what to suggest for the next batter (mirrors R's
/// `lookup_jersey_for_spot`). Once the lineup is locked (see
/// [AppSession.lineupLocked]), this suggestion is auto-committed as the
/// starting jersey # for the next batter — no "Submit #" step required —
/// and can still be corrected live at any time via
/// [AppSession.updateCommittedJersey]. Before the lineup locks (i.e. for
/// the very first batter), the person still submits jersey + order
/// together via "Submit #".
class PitchAddResult {
  final bool endedAB;
  final int nextBattingOrder;
  final int? suggestedJersey;
  final String? suggestedHand;
  const PitchAddResult({
    required this.endedAB,
    required this.nextBattingOrder,
    this.suggestedJersey,
    this.suggestedHand,
  });
}

/// A snapshot of every piece of live game-input state that [AppSession.addPitch]
/// and [AppSession._addNonPitchEvent] can change, captured right *before*
/// the mutation. [AppSession.undoLastPitch] restores from this instead of
/// recomputing from the saved pitch log, so balls/strikes/pitchNumInAB
/// (which can't be reliably re-derived after the fact) come back exactly
/// as they were.
class _GameStateSnapshot {
  final String currentOpponent;
  final int currentGameNumber;
  final int currentSeason;
  final int battingOrderSlot;
  final int? committedJersey;
  final String hand;
  final int balls;
  final int strikes;
  final int outs;
  final int pitchNumInAB;
  final int paCounter;
  final int completedPAs;
  final int lineupSize;
  final int currentInning;
  const _GameStateSnapshot({
    required this.currentOpponent,
    required this.currentGameNumber,
    required this.currentSeason,
    required this.battingOrderSlot,
    required this.committedJersey,
    required this.hand,
    required this.balls,
    required this.strikes,
    required this.outs,
    required this.pitchNumInAB,
    required this.paCounter,
    required this.completedPAs,
    required this.lineupSize,
    required this.currentInning,
  });
}

class AppSession extends ChangeNotifier {
  final AuthService auth;
  final StorageService storage;
  final _uuid = const Uuid();

  AppSession({required this.auth, required this.storage});

  AppUser? currentUser;
  List<PitchEvent> pitches = [];

  // ── Live game-input state machine (mirrors R's `gs` reactiveValues) ──
  String currentOpponent = '';
  int currentGameNumber = 1;
  int currentSeason = DateTime.now().year;
  int battingOrderSlot = 1;
  int? committedJersey;
  String hand = 'R';
  int balls = 0;
  int strikes = 0;
  int outs = 0;
  int pitchNumInAB = 1;
  int _paCounter = 0; // increments every time a new PA starts

  /// Current half-inning number for the game in progress. Starts at 1 and
  /// auto-advances the instant the third out of the frame is recorded
  /// (mirrored in [addPitch] and [_addNonPitchEvent], right alongside the
  /// existing outs/count reset), so History, the batter header, and the
  /// Batter History section always show a real inning without the pitcher
  /// having to set it by hand.
  int currentInning = 1;

  /// One snapshot per pitch/event added from Game Input, in order, so
  /// [undoLastPitch] can restore the exact prior state (see
  /// [_GameStateSnapshot]). Cleared any time the pitch log is mutated
  /// through a path other than [addPitch]/[_addNonPitchEvent] (manual add,
  /// edit, delete, or a new game), since the stack would no longer line up
  /// with the tail of [pitches] at that point.
  final List<_GameStateSnapshot> _undoStack = [];

  _GameStateSnapshot _captureSnapshot() => _GameStateSnapshot(
        currentOpponent: currentOpponent,
        currentGameNumber: currentGameNumber,
        currentSeason: currentSeason,
        battingOrderSlot: battingOrderSlot,
        committedJersey: committedJersey,
        hand: hand,
        balls: balls,
        strikes: strikes,
        outs: outs,
        pitchNumInAB: pitchNumInAB,
        paCounter: _paCounter,
        completedPAs: completedPAs,
        lineupSize: lineupSize,
        currentInning: currentInning,
      );

  /// Outcomes that end a plate appearance — shared by [addPitch] (to decide
  /// when to bump [completedPAs]) and [_restoreCountersFromHistory] (to
  /// decide, when resuming, whether the last logged batter's PA was already
  /// finished or is still in progress).
  static const Set<String> _abEndingOutcomes = {
    '1b', '2b', '3b', 'hr', 'go', 'fo', 'lo', 'dp', 'e', 'fc', 'bb', 'hbp',
    'k', 'kl', 'dk',
  };

  /// Value of [lineupSize] meaning "this lineup is longer than the standard 9
  /// and its length isn't known yet" — the order just keeps counting up
  /// (10, 11, 12, ...) until the person enters spot 1 again.
  static const int openLineup = 99;

  /// Lineup length: the batting order wraps back to spot 1 automatically
  /// once it reaches this. Starts at the standard 9 and is learned from how
  /// the lineup is actually entered:
  ///  * entering a spot above the current size (e.g. 10) means the lineup is
  ///    longer than assumed, so the size becomes [openLineup] — the order
  ///    keeps incrementing normally;
  ///  * entering spot 1 while a higher spot was due next means the lineup has
  ///    wrapped, and the size becomes the highest spot used (8, 13, ...), so
  ///    every later cycle wraps there on its own.
  /// See [updateBattingOrderSlot].
  int lineupSize = 9;

  /// Jersey # → player name, for display/edit purposes only (never used in
  /// stat calculations). Persists per user, independent of any one game.
  Map<int, String> batterNames = {};

  /// "Batters Faced" for the live Game Input screen — a count of *completed*
  /// plate appearances, not a batter ID and not a pitch counter.
  ///
  /// Starts at 0. It must display 0 for the entire first at-bat (nobody has
  /// been fully faced yet), and only becomes 1 the instant that first PA
  /// ends — then holds at 1 for the entire second at-bat, becomes 2 when
  /// that one ends, and so on. This is a real stored counter, not something
  /// recomputed from a "max batter id" on every read (that was the original
  /// bug: it recomputed itself upward on every single pitch). It only ever
  /// advances by 1 in [addPitch], once, right after a plate appearance
  /// actually ends. Editing, deleting, or undoing pitches never touches it
  /// directly — those flows all go through [_restoreCountersFromHistory],
  /// which recomputes the correct count fresh from the saved data:
  ///  - Deleting pitches from the *current, unfinished* PA leaves the count
  ///    unchanged (that PA still isn't complete).
  ///  - Deleting an entire *completed* PA decreases the count by 1 (that
  ///    batter is no longer considered faced).
  ///  - Deleting every pitch resets the count to 0.
  int completedPAs = 0;

  /// User-defined pitch type keys (lowercase, trimmed — e.g. "knuckleball")
  /// added on Game Input, on top of the built-in fb/cv/ch/sl set. Replaces
  /// the old "Other" button. Unlike the built-ins, these have no length or
  /// character restriction — see [addCustomPitchType].
  List<String> customPitchTypes = [];

  /// Key → the exact display name the person typed in (e.g. "Knuckleball"),
  /// so full pitch names can be shown everywhere instead of the internal
  /// key. Built-in types are named by [builtInPitchTypeFullNames] instead.
  Map<String, String> customPitchTypeNames = {};

  /// Key → the color the person picked when creating that pitch type. Kept
  /// in sync with [AppColors]'s override table (via [_syncPitchColors]) so
  /// this exact color is used everywhere that pitch type appears — the
  /// button, the spray chart, pitch history, pitch breakdown, and every
  /// other pitch visualization use the same [AppColors.pitchColor] lookup.
  Map<String, Color> customPitchTypeColors = {};

  /// Full display names for the four built-in pitch types, used by
  /// [pitchTypeLabel] and shared by every screen that needs a pitch type's
  /// full name instead of its short internal key.
  static const Map<String, String> builtInPitchTypeFullNames = {
    'fb': 'Fastball',
    'cv': 'Curveball',
    'ch': 'Changeup',
    'sl': 'Slider',
  };

  /// Full display name for a pitch type key (built-in or custom), for use
  /// anywhere a pitch type is shown to the person — pitch buttons, Call
  /// screen headers, History, Batter History, etc. Falls back to the raw
  /// key (capitalized) if it's neither a known built-in nor a saved custom
  /// type, so nothing ever renders blank.
  String pitchTypeLabel(String? key) {
    if (key == null || key.trim().isEmpty) return 'Other';
    final k = key.toLowerCase().trim();
    // The pitcher's own names always win. The legacy names below only label
    // old rows that were logged with the removed fb/cv/ch/sl presets.
    if (customPitchTypeNames.containsKey(k)) return customPitchTypeNames[k]!;
    if (builtInPitchTypeFullNames.containsKey(k)) {
      return builtInPitchTypeFullNames[k]!;
    }
    // Older saved data may reference a pitch type key that predates full
    // display names (e.g. a short code typed before this feature existed).
    // Show it title-cased rather than leaving it blank or all-lowercase.
    return k.isEmpty ? 'Other' : (k[0].toUpperCase() + k.substring(1));
  }

  /// Pushes the current custom pitch colors into [AppColors]'s shared
  /// override table so every screen's [AppColors.pitchColor] calls stay in
  /// sync — called once on login/logout and any time a custom color is
  /// added, changed, or removed.
  void _syncPitchColors() {
    AppColors.setCustomPitchColors(customPitchTypeColors);
  }

  /// Built-in pitch type codes (FB/CV/CH/SL) the user has chosen to hide
  /// from the Game Input pitch-type row. Pitches already logged with a
  /// hidden built-in code keep their data — this only affects which
  /// buttons are shown, mirroring how custom pitch types can be removed.
  List<String> hiddenBuiltInPitchTypes = [];

  // ── Pitcher profiles (one login, several pitchers) ──────────────
  // Every pitch, game, bullpen and setting belongs to the ACTIVE pitcher.
  final PitcherService pitcherService = PitcherService();
  List<Pitcher> pitchers = [];
  Pitcher? activePitcher;

  /// True while a different pitcher's data is being loaded.
  bool switchingPitcher = false;

  /// Set by the home shell so the Bullpen store reloads on a switch.
  VoidCallback? onActivePitcherChanged;

  /// Id every data read/write is keyed by. Falls back to the account id (the
  /// account's first pitcher always shares it) only before pitchers load.
  String get activePitcherId => activePitcher?.id ?? currentUser?.id ?? '';
  String get activePitcherName =>
      activePitcher?.displayName ?? currentUser?.pitcherDisplayName ?? '—';

  int get pitcherLimit => currentUser?.maxPitchers ?? 1;
  bool get canAddPitcher => pitchers.length < pitcherLimit;

  bool get isLoggedIn => currentUser != null;
  /// Every plan includes every feature; nothing is locked.
  bool get isPlus => true;

  /// True once the very first plate appearance of the lineup has
  /// completed. Before this, the batting order is still being bootstrapped
  /// (jersey # + order spot both need to be entered via "Submit #"). After
  /// this point the order itself auto-advances and is no longer manually
  /// edited — only the jersey # of whoever is currently up stays editable,
  /// live, with no submit step (see [updateCommittedJersey]).
  bool get lineupLocked => completedPAs >= 1;

  // ── Year filter (used by the small year dropdown on every stats screen) ──
  int? selectedYear; // null = All years

  List<int> get availableYears {
    final years = pitches.map((p) => p.season).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Pitches narrowed to [selectedYear], or all pitches if no year is chosen.
  List<PitchEvent> get filteredPitches => selectedYear == null
      ? pitches
      : pitches.where((p) => p.season == selectedYear).toList();

  void setSelectedYear(int? year) {
    selectedYear = year;
    notifyListeners();
  }

  Future<void> login(AppUser user) async {
    currentUser = user;
    await refreshPitchers(keepActive: false);
    await _loadActivePitcherData();
    notifyListeners();
  }

  /// Reloads the pitcher list. Keeps the same active pitcher if it still exists.
  Future<void> refreshPitchers({bool keepActive = true}) async {
    var list = await pitcherService.loadPitchers();
    if (list.isEmpty) {
      try {
        await pitcherService.ensureDefaultPitcher();
        list = await pitcherService.loadPitchers();
      } catch (_) {}
    }
    pitchers = list;
    final keepId = keepActive ? activePitcher?.id : null;
    Pitcher? next;
    for (final p in list) {
      if (p.id == keepId) next = p;
    }
    activePitcher = next ?? (list.isNotEmpty ? list.first : null);
    notifyListeners();
  }

  /// Loads the ACTIVE pitcher's games, pitches and settings, replacing
  /// whatever was in memory (nothing from another pitcher is kept).
  Future<void> _loadActivePitcherData() async {
    final id = activePitcherId;
    pitches = await storage.loadPitchesForUser(id);
    customPitchTypes = await storage.loadCustomPitchTypes(id);
    hiddenBuiltInPitchTypes = await storage.loadHiddenBuiltInPitchTypes(id);
    batterNames = await storage.loadBatterNames(id);
    customPitchTypeNames = await storage.loadCustomPitchTypeNames(id);
    final storedColors = await storage.loadCustomPitchTypeColors(id);
    customPitchTypeColors = storedColors.map((k, v) => MapEntry(k, Color(v)));
    _syncPitchColors();
    selectedYear = null;
    _resetLiveState(); // a game in progress belongs to the previous pitcher
    _restoreCountersFromHistory();
  }

  /// Makes [p] the active pitcher everywhere in the app. All data is cleared
  /// and re-loaded for that pitcher before anything can be saved again.
  Future<void> switchPitcher(Pitcher p) async {
    if (p.id == activePitcher?.id || switchingPitcher) return;
    switchingPitcher = true;
    notifyListeners();
    try {
      activePitcher = p;
      pitches = []; // never show or save the previous pitcher's data
      await _loadActivePitcherData();
      onActivePitcherChanged?.call();
    } finally {
      switchingPitcher = false;
      notifyListeners();
    }
  }

  /// Clears local session state AND signs out of Supabase (otherwise the
  /// persisted Supabase session would silently log this device back in
  /// next launch via [AuthService.restoreSession]).
  Future<void> logout() async {
    await auth.logout();
    currentUser = null;
    pitchers = [];
    activePitcher = null;
    switchingPitcher = false;
    pitches = [];
    customPitchTypes = [];
    hiddenBuiltInPitchTypes = [];
    batterNames = {};
    customPitchTypeNames = {};
    customPitchTypeColors = {};
    _syncPitchColors();
    _resetLiveState();
    notifyListeners();
  }

  void _resetLiveState() {
    currentOpponent = '';
    currentGameNumber = 1;
    currentSeason = DateTime.now().year;
    battingOrderSlot = 1;
    committedJersey = null;
    hand = 'R';
    balls = 0;
    strikes = 0;
    outs = 0;
    pitchNumInAB = 1;
    _paCounter = 0;
    completedPAs = 0;
    lineupSize = 9;
    currentInning = 1;
    _undoStack.clear();
  }

  void _restoreCountersFromHistory() {
    if (pitches.isEmpty) {
      _paCounter = 0;
      completedPAs = 0;
      return;
    }
    final maxPaId =
        pitches.map((p) => p.paId).fold<int>(0, (a, b) => a > b ? a : b);
    _paCounter = maxPaId;
    final last = pitches.last;
    currentOpponent = last.game;
    currentGameNumber = last.gameNumber;
    currentSeason = last.season;
    committedJersey = last.batterNumber;
    battingOrderSlot = last.battingOrder;
    outs = last.outs >= 3 ? 0 : last.outs;
    // Resume from the last logged inning, if any row in this game recorded
    // one (older saved data may predate inning tracking and have none).
    final lastInning = pitches
        .where((p) =>
            p.game == currentOpponent &&
            p.gameNumber == currentGameNumber &&
            p.season == currentSeason &&
            p.inning != null)
        .map((p) => p.inning!)
        .fold<int?>(null, (a, b) => a == null ? b : (b > a ? b : a));
    currentInning = lastInning ?? 1;

    // Batters Faced ("completed PAs") — recomputed fresh from the saved log,
    // never trusted as a running total, so deletes/edits/undos can't drift
    // it. Look at the last real pitch row (skipping pickoffs/throwouts,
    // which aren't a batter's own PA). That row's `batter` value is exactly
    // "how many PAs were completed before this one started" — because
    // that's what addPitch stamped onto it. So:
    //  - If that row's PA already ended, one more PA is now complete:
    //    completedPAs = lastPitchRow.batter + 1.
    //  - If that row's PA is still in progress (mid at-bat), nothing new
    //    has completed yet: completedPAs = lastPitchRow.batter, unchanged.
    final lastPitchRow =
        pitches.reversed.firstWhere((p) => p.eventType == 'pitch', orElse: () => last);
    final lastPaEnded = lastPitchRow.outcome != null &&
        _abEndingOutcomes.contains(lastPitchRow.outcome);
    completedPAs =
        lastPaEnded ? lastPitchRow.batter + 1 : lastPitchRow.batter;
    lineupSize = _inferLineupSize();
  }

  /// Known opponent names logged so far (for the dropdown), mirrors
  /// `known_teams()`.
  List<String> get knownTeams =>
      pitches.map((p) => p.game).toSet().toList()..sort();

  void setGame(String opponent, int gameNumber, [int? season]) {
    final changed = opponent != currentOpponent || gameNumber != currentGameNumber;
    currentOpponent = opponent;
    currentGameNumber = gameNumber;
    if (season != null) currentSeason = season;
    if (changed) {
      // A new team or a new game number is treated as an entirely new
      // game: the batting order resets, the lineup unlocks (every spot
      // editable again), and every piece of state that only makes sense
      // for a single game in progress starts clean. Historical pitches
      // already logged are untouched — this only resets the *live* input
      // state machine.
      battingOrderSlot = 1;
      committedJersey = null;
      lineupSize = 9;
      completedPAs = 0; // completedPAs == 0 is what makes lineupLocked false again
      balls = 0;
      strikes = 0;
      outs = 0;
      pitchNumInAB = 1;
      _paCounter = 0;
      currentInning = 1;
      _undoStack.clear();
    }
    notifyListeners();
  }

  /// Corrects the identifying info (team name, game number, year) of the
  /// *currently active* game in place — e.g. fixing a misspelled opponent
  /// name. Renames every already-saved pitch/event row that belongs to
  /// this game to match the correction, and updates the live
  /// opponent/gameNumber/season fields. Unlike [setGame], this never
  /// resets the batting order, lineup lock, count, or outs — it's a pure
  /// correction to an in-progress game, not the start of a new one.
  Future<void> editCurrentGameInfo(
      String newOpponent, int newGameNumber, int newSeason) async {
    if (currentUser == null || switchingPitcher) return;
    final oldOpponent = currentOpponent;
    final oldGameNumber = currentGameNumber;
    final oldSeason = currentSeason;
    if (newOpponent == oldOpponent &&
        newGameNumber == oldGameNumber &&
        newSeason == oldSeason) {
      return;
    }
    for (var i = 0; i < pitches.length; i++) {
      final p = pitches[i];
      if (p.game == oldOpponent &&
          p.gameNumber == oldGameNumber &&
          p.season == oldSeason) {
        pitches[i] = p.copyWith(
            game: newOpponent, gameNumber: newGameNumber, season: newSeason);
      }
    }
    currentOpponent = newOpponent;
    currentGameNumber = newGameNumber;
    currentSeason = newSeason;
    await storage.savePitchesForUser(activePitcherId, pitches);
    notifyListeners();
  }

  void setBatter(int jersey, int battingOrder) {
    committedJersey = jersey;
    battingOrderSlot = battingOrder;
    _paCounter++;
    balls = 0;
    strikes = 0;
    pitchNumInAB = 1;
    notifyListeners();
  }

  void setHand(String h) {
    hand = h;
    notifyListeners();
  }

  /// Corrects the currently-active batter's jersey # in place. Unlike
  /// [setBatter], this never starts a new plate appearance and never
  /// touches the PA counter, balls/strikes, or batting order — it just
  /// overwrites the jersey # so a typo can be fixed at any time (once the
  /// lineup has locked) without unlocking or resetting anything else.
  void updateCommittedJersey(int? jersey) {
    committedJersey = jersey;
    notifyListeners();
  }

  /// Lets the batting order be corrected live at any time — before or
  /// after the lineup locks — same as [updateCommittedJersey] does for the
  /// jersey #. No Submit step, never touches the PA counter.
  ///
  /// Lineup-cycle rules (see [lineupSize]):
  ///  * **1 starts a new cycle.** If the order was about to continue at spot
  ///    N > 1 and the person enters 1, the lineup has wrapped: its length is
  ///    the highest spot actually used this game (at least N - 1), and the
  ///    order counts 2, 3, 4 ... from here, wrapping at that length.
  ///  * **10 and up keep counting.** A spot above the current lineup length
  ///    means the lineup is longer than assumed, so the order simply keeps
  ///    incrementing (10 → 11 → 12 ...) until 1 is entered again.
  void updateBattingOrderSlot(int slot) {
    if (slot < 1) return;
    final due = battingOrderSlot;
    if (slot == 1 && due > 1) {
      final highest = _highestOrderThisGame();
      final size = (due - 1) > highest ? (due - 1) : highest;
      lineupSize = size < 1 ? 1 : size;
    } else if (slot > lineupSize) {
      lineupSize = openLineup;
    }
    battingOrderSlot = slot;
    notifyListeners();
  }

  /// Highest batting-order spot logged so far in the current game (0 if none).
  int _highestOrderThisGame() {
    var highest = 0;
    for (final p in pitches) {
      if (p.game == currentOpponent &&
          p.gameNumber == currentGameNumber &&
          p.season == currentSeason &&
          p.battingOrder > highest) {
        highest = p.battingOrder;
      }
    }
    return highest;
  }

  /// Rebuilds [lineupSize] from the saved log when a game is resumed: a
  /// spot-1 batter showing up after higher spots means the lineup wrapped at
  /// the highest spot seen; spots of 10+ with no wrap yet mean the lineup is
  /// still open-ended; otherwise the standard 9.
  int _inferLineupSize() {
    var highest = 0;
    var wrapped = false;
    int? lastPa;
    for (final p in pitches) {
      if (p.game != currentOpponent ||
          p.gameNumber != currentGameNumber ||
          p.season != currentSeason) {
        continue;
      }
      if (p.paId == lastPa) continue; // same plate appearance
      lastPa = p.paId;
      if (p.battingOrder == 1 && highest > 1) wrapped = true;
      if (p.battingOrder > highest) highest = p.battingOrder;
    }
    if (wrapped) return highest;
    return highest >= 10 ? openLineup : 9;
  }

  /// Sets/updates a display name for a jersey #, purely for the person's
  /// own reference (never used in any stat calculation). Persists across
  /// games for this user.
  Future<void> setBatterName(int jersey, String name) async {
    if (currentUser == null || switchingPitcher) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      batterNames.remove(jersey);
    } else {
      batterNames[jersey] = trimmed;
    }
    await storage.saveBatterNames(activePitcherId, batterNames);
    notifyListeners();
  }

  /// Looks up the last jersey number that batted in [spot] in the current
  /// game (same opponent + game number), so that wrapping back around the
  /// order can suggest who's up without the person having to remember.
  /// Mirrors R's `lookup_jersey_for_spot`.
  int? lookupJerseyForSpot(int spot) {
    if (currentOpponent.isEmpty) return null;
    for (final p in pitches.reversed) {
      if (p.game == currentOpponent &&
          p.gameNumber == currentGameNumber &&
          p.battingOrder == spot &&
          p.batterNumber != null) {
        return p.batterNumber;
      }
    }
    return null;
  }

  /// Same idea as [lookupJerseyForSpot] but for batter hand, so the L/R
  /// toggle can restore itself too when a spot in the order comes back up.
  String? lookupHandForSpot(int spot) {
    if (currentOpponent.isEmpty) return null;
    for (final p in pitches.reversed) {
      if (p.game == currentOpponent &&
          p.gameNumber == currentGameNumber &&
          p.battingOrder == spot) {
        return p.hand;
      }
    }
    return null;
  }

  /// Adds a new user-defined pitch type (e.g. typing "Knuckleball") and
  /// persists it, along with its display name and — if given — its color.
  /// The full name is entered with no artificial character limit (unlike
  /// the old short-code system). There are no preset pitches, so every
  /// pitch type is one the person created. Returns the key the pitch was
  /// stored under, or null if the name was blank.
  Future<String?> addCustomPitchType(String name, {Color? color}) async {
    if (currentUser == null || switchingPitcher) return null;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final key = trimmedName.toLowerCase();
    if (!customPitchTypes.contains(key)) {
      customPitchTypes.add(key);
    }
    customPitchTypeNames[key] = trimmedName;
    if (color != null) {
      customPitchTypeColors[key] = color;
      _syncPitchColors();
    }
    await storage.saveCustomPitchTypes(activePitcherId, customPitchTypes);
    await storage.saveCustomPitchTypeNames(activePitcherId, customPitchTypeNames);
    await storage.saveCustomPitchTypeColors(
        activePitcherId, customPitchTypeColors.map((k, v) => MapEntry(k, v.value)));
    notifyListeners();
    return key;
  }

  /// Changes the color of an existing custom pitch type. That exact color
  /// is then used everywhere the pitch appears — button, spray chart,
  /// history, breakdown — since every screen reads through
  /// [AppColors.pitchColor], which is kept in sync via [_syncPitchColors].
  Future<void> setCustomPitchTypeColor(String key, Color color) async {
    if (currentUser == null || switchingPitcher) return;
    final k = key.toLowerCase().trim();
    customPitchTypeColors[k] = color;
    _syncPitchColors();
    await storage.saveCustomPitchTypeColors(
        activePitcherId, customPitchTypeColors.map((k, v) => MapEntry(k, v.value)));
    notifyListeners();
  }

  /// Removes a previously-added custom pitch type button. Pitches already
  /// logged with it keep their data and their color (removing only hides
  /// the button — [pitchTypeLabel] and [AppColors.pitchColor] still resolve
  /// it consistently for anything already saved).
  Future<void> removeCustomPitchType(String code) async {
    if (currentUser == null || switchingPitcher) return;
    final key = code.toLowerCase().trim();
    customPitchTypes.remove(key);
    await storage.saveCustomPitchTypes(activePitcherId, customPitchTypes);
    notifyListeners();
  }

  /// Hides one of the built-in pitch type buttons (FB/CV/CH/SL) from the
  /// Game Input pitch-type row. Pitches already logged with this code keep
  /// their data — this is purely a display preference, same as removing a
  /// custom pitch type.
  Future<void> hideBuiltInPitchType(String code) async {
    if (currentUser == null || switchingPitcher) return;
    final c = code.trim().toUpperCase();
    if (!hiddenBuiltInPitchTypes.contains(c)) {
      hiddenBuiltInPitchTypes.add(c);
      await storage.saveHiddenBuiltInPitchTypes(
          activePitcherId, hiddenBuiltInPitchTypes);
      notifyListeners();
    }
  }

  /// Restores every previously-hidden built-in pitch type button.
  Future<void> restoreBuiltInPitchTypes() async {
    if (currentUser == null || switchingPitcher) return;
    hiddenBuiltInPitchTypes = [];
    await storage.saveHiddenBuiltInPitchTypes(activePitcherId, hiddenBuiltInPitchTypes);
    notifyListeners();
  }

  /// Logs one pitch event, applying the same count/out state machine as
  /// the R app's `add_pitch` observer (ball/strike/foul handling, PA-ending
  /// outcome inference, and out increments for GO/FO/LO/FC/DP/K).
  Future<PitchAddResult> addPitch({
    required String pitchType,
    required String call,
    String? bipOutcome,
    double? xCoord,
    double? yCoord,
    String? battedType,
    double er = 0,
  }) async {
    if (currentUser == null || switchingPitcher) {
      return PitchAddResult(endedAB: false, nextBattingOrder: battingOrderSlot);
    }
    _undoStack.add(_captureSnapshot());
    String? outcome = bipOutcome;
    bool endAB = false;

    switch (call) {
      case 'b':
        balls++;
        if (balls >= 4) {
          endAB = true;
          outcome = 'bb';
        }
        break;
      case 'ss': // swinging strike
        strikes++;
        if (strikes >= 3) {
          endAB = true;
          outcome = 'k';
        }
        break;
      case 'sl': // called strike (looking)
        strikes++;
        if (strikes >= 3) {
          endAB = true;
          outcome = 'kl';
        }
        break;
      case 'f': // foul
        if (strikes < 2) strikes++;
        break;
      case 'hbp':
        endAB = true;
        outcome = 'hbp';
        break;
      case 'dk': // dead ball / no pitch
        endAB = true;
        outcome = 'dk';
        break;
      case 'ip': // ball in play
        endAB = true;
        break;
    }

    if (outcome != null && _abEndingOutcomes.contains(outcome)) {
      endAB = true;
    }

    // Out increments, mirrors R: K/GO/FO/LO/FC = +1 out, DP = +2 outs.
    if ({'k', 'kl', 'fo', 'lo', 'go', 'fc'}.contains(outcome)) {
      outs = (outs + 1).clamp(0, 3);
    } else if (outcome == 'dp') {
      outs = (outs + 2).clamp(0, 3);
    }

    final ev = PitchEvent(
      id: _uuid.v4(),
      userId: activePitcherId,
      game: currentOpponent,
      gameNumber: currentGameNumber,
      batter: completedPAs,
      batterNumber: committedJersey,
      battingOrder: battingOrderSlot,
      hand: hand,
      eventType: 'pitch',
      pitchNum: pitchNumInAB,
      pitchType: pitchType,
      call: call,
      outcome: outcome,
      ab: (outcome != null && !{'bb', 'hbp'}.contains(outcome)) ? 1 : 0,
      outs: outs,
      er: er,
      xCoord: xCoord,
      yCoord: yCoord,
      battedType: battedType,
      inning: currentInning,
      paId: _paCounter,
      season: currentSeason,
    );

    pitches.add(ev);
    await storage.savePitchesForUser(activePitcherId, pitches);

    if (outs >= 3) {
      outs = 0;
      currentInning++;
    }

    if (endAB) {
      balls = 0;
      strikes = 0;
      pitchNumInAB = 1;
      // The PA that was just recorded is now complete — that's exactly one
      // more "batter faced". This is the only place this counter ever
      // moves: once, here, right after a PA ends. It never moves on a
      // mid-PA pitch, an edit, or a re-save.
      completedPAs++;
      // The order wraps back to spot 1 once it passes lineupSize (default
      // 9) — see [updateBattingOrderSlot] for how lineupSize can shrink if
      // this team's lineup turns out to be shorter.
      final wrap = battingOrderSlot >= lineupSize;
      battingOrderSlot = wrap ? 1 : battingOrderSlot + 1;
      final suggestedJersey = lookupJerseyForSpot(battingOrderSlot);
      final suggestedHand = lookupHandForSpot(battingOrderSlot);
      if (suggestedHand != null) hand = suggestedHand;
      // Once the lineup has locked (this is always true here, since
      // completedPAs was just bumped above), the next batter's jersey #
      // is live-editable in the UI with no Submit step — so auto-fill the
      // history suggestion (if any) as the starting point instead of
      // leaving it null and waiting on a button press. If there's no
      // history for this spot yet, it just starts blank and the person
      // types the number, which auto-saves as they type.
      committedJersey = lineupLocked ? suggestedJersey : null;
      notifyListeners();
      return PitchAddResult(
        endedAB: true,
        nextBattingOrder: battingOrderSlot,
        suggestedJersey: suggestedJersey,
        suggestedHand: suggestedHand,
      );
    } else {
      pitchNumInAB++;
      notifyListeners();
      return PitchAddResult(endedAB: false, nextBattingOrder: battingOrderSlot);
    }
  }

  /// Shared implementation for the three "not a pitch" game-event buttons
  /// (Pickoff, Caught Stealing, Balk). These never touch balls, strikes,
  /// pitch counts, or pitch-type stats, and never create a `pitch`-typed
  /// row — [StatsService.pitchesOnly] and [StatsService.finalPAs] both key
  /// off `eventType == 'pitch'`, so anything logged here is automatically
  /// excluded from every pitching/pitch-usage stat. [recordsOut] controls
  /// whether it also advances the outs count (true for PO/CS, false for a
  /// balk, which affects nothing but still gets a row for the record).
  Future<void> _addNonPitchEvent({
    required String eventType,
    required String outcome,
    required bool recordsOut,
  }) async {
    if (currentUser == null || switchingPitcher) return;
    _undoStack.add(_captureSnapshot());
    if (recordsOut) {
      outs = (outs + 1).clamp(0, 3);
    }
    final ev = PitchEvent(
      id: _uuid.v4(),
      userId: activePitcherId,
      game: currentOpponent,
      gameNumber: currentGameNumber,
      batter: completedPAs,
      batterNumber: committedJersey,
      battingOrder: battingOrderSlot,
      hand: hand,
      eventType: eventType,
      pitchNum: null,
      pitchType: null,
      call: eventType,
      outcome: outcome,
      ab: 0,
      outs: outs,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: null,
      inning: currentInning,
      paId: _paCounter,
      season: currentSeason,
    );
    pitches.add(ev);
    await storage.savePitchesForUser(activePitcherId, pitches);
    // If this PO/CS was the third out of the inning, the frame ends but the
    // plate appearance does not: the same batter leads off next inning, so
    // the count resets to 0-0 while Batters Faced and the batting order stay
    // untouched (mirrors real baseball rules).
    if (recordsOut && outs >= 3) {
      outs = 0;
      balls = 0;
      strikes = 0;
      pitchNumInAB = 1;
      currentInning++;
    }
    notifyListeners();
  }

  /// PO — runner picked off. Not a pitch: doesn't touch pitch totals or
  /// pitch-type stats, doesn't create a pitch record. Records one out.
  Future<void> addPickoff() => _addNonPitchEvent(
      eventType: 'po', outcome: 'po_out', recordsOut: true);

  /// CS — runner caught stealing. Not a pitch: doesn't touch pitch totals
  /// or pitch usage stats, doesn't create a pitch record. Records one out.
  Future<void> addCaughtStealing() =>
      _addNonPitchEvent(eventType: 'to', outcome: 'to', recordsOut: true);

  /// TO — runner/batter thrown out on a batted ball (e.g. thrown out at
  /// first or a base on a fielded ball that isn't scored as a standard
  /// GO/FO/LO out). Behaves exactly like PO/CS: not a pitch, doesn't touch
  /// pitch totals or pitch-usage stats, doesn't create a pitch record.
  /// Records one out. Uses its own eventType ('txo') so it's never
  /// conflated with the legacy Caught Stealing rows (which are internally
  /// stored as eventType 'to').
  Future<void> addThrowOut() =>
      _addNonPitchEvent(eventType: 'txo', outcome: 'txo', recordsOut: true);

  /// BK — balk. Not a pitch and doesn't affect any pitching statistics:
  /// no pitch record, no effect on pitch totals/pitch-type stats, no
  /// batter effect, no out, no batter advancement. Exists purely so the
  /// pitch log can note that a balk happened.
  Future<void> addBalk() =>
      _addNonPitchEvent(eventType: 'bk', outcome: 'bk', recordsOut: false);

  /// Completely restores the game to the exact state it was in before the
  /// last pitch/event logged from Game Input — as if it had never been
  /// entered. Removes the row itself and, when a matching snapshot is
  /// available (see [_GameStateSnapshot]), restores balls, strikes, outs,
  /// pitch #, batting order, jersey, hand, Batters Faced, and every other
  /// piece of live game state exactly, not just an approximation
  /// recomputed after the fact.
  Future<void> undoLastPitch() async {
    if (currentUser == null || switchingPitcher || pitches.isEmpty) return;
    if (_undoStack.isNotEmpty) {
      final snap = _undoStack.removeLast();
      pitches.removeLast();
      await storage.savePitchesForUser(activePitcherId, pitches);
      currentOpponent = snap.currentOpponent;
      currentGameNumber = snap.currentGameNumber;
      currentSeason = snap.currentSeason;
      battingOrderSlot = snap.battingOrderSlot;
      committedJersey = snap.committedJersey;
      hand = snap.hand;
      balls = snap.balls;
      strikes = snap.strikes;
      outs = snap.outs;
      pitchNumInAB = snap.pitchNumInAB;
      _paCounter = snap.paCounter;
      completedPAs = snap.completedPAs;
      lineupSize = snap.lineupSize;
      currentInning = snap.currentInning;
    } else {
      // No snapshot to restore from (e.g. the last row wasn't logged from
      // Game Input in this session) — fall back to removing the row and
      // recomputing what can be recomputed from the saved log.
      pitches.removeLast();
      await storage.savePitchesForUser(activePitcherId, pitches);
      _restoreCountersFromHistory();
    }
    notifyListeners();
  }

  /// Adds a fully-formed row from the Edit Raw Data screen's "Add Row"
  /// dialog — doesn't touch the live game-input state machine (balls,
  /// strikes, outs, batting order), unlike [addPitch]. Always appends to
  /// the end of the log; see [insertPitchAt] to insert somewhere else.
  Future<void> addManualPitch(PitchEvent event) async {
    if (currentUser == null || switchingPitcher) return;
    pitches.add(event);
    await storage.savePitchesForUser(activePitcherId, pitches);
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  /// Same as [addManualPitch], but inserts the row at [index] instead of
  /// appending — lets Edit Raw Data insert a row anywhere in the log, e.g.
  /// between two existing rows, not just at the end.
  Future<void> insertPitchAt(int index, PitchEvent event) async {
    if (currentUser == null || switchingPitcher) return;
    final at = index.clamp(0, pitches.length);
    pitches.insert(at, event);
    await storage.savePitchesForUser(activePitcherId, pitches);
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  Future<void> deletePitchAt(int index) async {
    if (currentUser == null || switchingPitcher) return;
    pitches.removeAt(index);
    await storage.savePitchesForUser(activePitcherId, pitches);
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  /// Wipes every pitch/pickoff/throwout row for the current user — rows
  /// logged live from Game Input, rows typed in via Edit Raw Data's "Add
  /// Row", everything. There's no separate "user-created" bucket; the
  /// pitch log is a single list, so this clears all of it.
  Future<void> deleteAllPitches() async {
    if (currentUser == null || switchingPitcher) return;
    pitches = [];
    await storage.savePitchesForUser(activePitcherId, pitches);
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  Future<void> updatePitchAt(int index, PitchEvent updated) async {
    if (currentUser == null || switchingPitcher) return;
    pitches[index] = updated;
    await storage.savePitchesForUser(activePitcherId, pitches);
    // Editing an at-bat/pitch never creates or removes a plate appearance,
    // so this is just keeping the live game-state fields (opponent, batting
    // order, completedPAs, etc.) in sync with the edited data — it can
    // never spuriously bump Batters Faced, since that's fully recomputed
    // from the saved rows every time (see _restoreCountersFromHistory).
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  Future<void> replaceAllPitches(List<PitchEvent> newPitches) async {
    if (currentUser == null || switchingPitcher) return;
    pitches = newPitches;
    await storage.savePitchesForUser(activePitcherId, pitches);
    _undoStack.clear();
    _restoreCountersFromHistory();
    notifyListeners();
  }

  /// Directly sets Outs for the live Game Input count bar — used when
  /// starting mid-inning (e.g. relieving with 1 out already on the board)
  /// so the person doesn't have to log fake outs just to get the counter
  /// right. Clamped to 0-3 and doesn't touch any other state.
  void setOuts(int value) {
    outs = value.clamp(0, 3);
    notifyListeners();
  }
}

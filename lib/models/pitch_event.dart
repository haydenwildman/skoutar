/// A single logged event — a pitch, a pickoff attempt ("po"), a runner
/// caught stealing ("to" — legacy internal name), a batted-ball throw out
/// ("txo"), or a balk ("bk"). This is a direct port of one row of the
/// R app's `raw_data` CSV (Game, game_number, Batter, Batter_number,
/// batting_order, L/R, event_type, Pitch_Num, Pitch_Type, Call, Outcome,
/// AB, Outs, ER, x_coord, y_coord, batted_type, inning).
///
/// Unlike the R app (which reconstructs plate-appearance boundaries from
/// raw pitch sequences after the fact), this Flutter port assigns `paId`
/// at write-time from the live game-state machine (see GameInputScreen),
/// which is simpler and numerically equivalent.
class PitchEvent {
  final String id;
  final String userId;
  final String game; // opponent name
  final int gameNumber;
  final int batter; // global plate-appearance sequence number for the game
  final int? batterNumber; // jersey #
  final int battingOrder; // 1-9 lineup spot
  final String hand; // 'L' or 'R'
  final String eventType; // 'pitch' | 'po' | 'to' | 'txo' | 'bk'
  final int? pitchNum; // pitch # within the at-bat (null for po/to/txo/bk)
  final String? pitchType; // fb, sl, cv, ch, other, or custom key
  final String? call; // b, ss, sl, dk, f, ip, hbp, po, to, txo, bk
  final String? outcome; // 1b,2b,3b,hr,go,fo,lo,dp,e,fc,bb,hbp,k,kl,dk,po_out,po_safe,to,txo,bk
  final int ab; // 1 if this pitch ended an at-bat that counts as an AB
  final int outs; // outs recorded AFTER this event (0-3, cumulative in the game)
  final double er; // earned runs charged on this event
  final double? xCoord;
  final double? yCoord;
  final String? battedType; // gb, ld, fb
  final int? inning;
  final int paId; // plate-appearance id (unique per game+batter spot cycle)
  final int season; // year this event belongs to (for the year filter)
  final DateTime timestamp;

  PitchEvent({
    required this.id,
    required this.userId,
    required this.game,
    required this.gameNumber,
    required this.batter,
    required this.batterNumber,
    required this.battingOrder,
    required this.hand,
    required this.eventType,
    required this.pitchNum,
    required this.pitchType,
    required this.call,
    required this.outcome,
    required this.ab,
    required this.outs,
    required this.er,
    required this.xCoord,
    required this.yCoord,
    required this.battedType,
    required this.inning,
    required this.paId,
    int? season,
    DateTime? timestamp,
  })  : timestamp = timestamp ?? DateTime.now(),
        season = season ?? (timestamp ?? DateTime.now()).year;

  /// Outcomes that count the batter as reaching base (hit).
  static const hitOutcomes = {'1b', '2b', '3b', 'hr'};
  static const walkOutcomes = {'bb'};
  /// Dropped third strike: the pitcher is credited with a strikeout, but the
  /// event itself records no out — the batter may reach first (see
  /// [AppSession.addPitch], `droppedThirdStrike`).
  static const droppedThirdStrikeOutcome = 'kdk';
  static const kOutcomes = {'k', 'kl', droppedThirdStrikeOutcome};
  static const ballInPlayOutOutcomes = {'go', 'fo', 'lo', 'dp', 'fc'};
  static const damageOutcomes = {'2b', '3b', 'hr', 'bb', 'hbp', 'e'};

  bool get isFinalPitchOfPA =>
      outcome != null &&
      outcome!.isNotEmpty &&
      outcome != 'po' &&
      eventType == 'pitch';

  int get totalBases => switch (outcome) {
        '1b' => 1,
        '2b' => 2,
        '3b' => 3,
        'hr' => 4,
        _ => 0,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'game': game,
        'gameNumber': gameNumber,
        'batter': batter,
        'batterNumber': batterNumber,
        'battingOrder': battingOrder,
        'hand': hand,
        'eventType': eventType,
        'pitchNum': pitchNum,
        'pitchType': pitchType,
        'call': call,
        'outcome': outcome,
        'ab': ab,
        'outs': outs,
        'er': er,
        'xCoord': xCoord,
        'yCoord': yCoord,
        'battedType': battedType,
        'inning': inning,
        'paId': paId,
        'season': season,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PitchEvent.fromJson(Map<String, dynamic> j) => PitchEvent(
        id: j['id'] as String,
        userId: j['userId'] as String,
        game: j['game'] as String,
        gameNumber: j['gameNumber'] as int,
        batter: j['batter'] as int,
        batterNumber: j['batterNumber'] as int?,
        battingOrder: j['battingOrder'] as int? ?? 1,
        hand: j['hand'] as String? ?? 'R',
        eventType: j['eventType'] as String? ?? 'pitch',
        pitchNum: j['pitchNum'] as int?,
        pitchType: j['pitchType'] as String?,
        call: j['call'] as String?,
        outcome: j['outcome'] as String?,
        ab: j['ab'] as int? ?? 0,
        outs: j['outs'] as int? ?? 0,
        er: (j['er'] as num?)?.toDouble() ?? 0,
        xCoord: (j['xCoord'] as num?)?.toDouble(),
        yCoord: (j['yCoord'] as num?)?.toDouble(),
        battedType: j['battedType'] as String?,
        inning: j['inning'] as int?,
        paId: j['paId'] as int? ?? 0,
        season: j['season'] as int? ??
            (DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now()).year,
        timestamp:
            DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );

  PitchEvent copyWith({
    String? game,
    int? gameNumber,
    int? batter,
    int? batterNumber,
    int? battingOrder,
    String? hand,
    String? eventType,
    int? pitchNum,
    String? pitchType,
    String? call,
    String? outcome,
    int? ab,
    int? outs,
    double? er,
    double? xCoord,
    double? yCoord,
    String? battedType,
    int? season,
  }) {
    return PitchEvent(
      id: id,
      userId: userId,
      game: game ?? this.game,
      gameNumber: gameNumber ?? this.gameNumber,
      batter: batter ?? this.batter,
      batterNumber: batterNumber ?? this.batterNumber,
      battingOrder: battingOrder ?? this.battingOrder,
      hand: hand ?? this.hand,
      eventType: eventType ?? this.eventType,
      pitchNum: pitchNum ?? this.pitchNum,
      pitchType: pitchType ?? this.pitchType,
      call: call ?? this.call,
      outcome: outcome ?? this.outcome,
      ab: ab ?? this.ab,
      outs: outs ?? this.outs,
      er: er ?? this.er,
      xCoord: xCoord ?? this.xCoord,
      yCoord: yCoord ?? this.yCoord,
      battedType: battedType ?? this.battedType,
      inning: inning,
      paId: paId,
      season: season ?? this.season,
      timestamp: timestamp,
    );
  }
}

import '../models/pitch_event.dart';
import 'scouting_report_data.dart';
import 'scouting_report_sheet.dart';

/// Keeps the Scouting Report screen's state and its computed report alive in
/// [AppSession] while the person visits other tabs (the tab body is rebuilt
/// from scratch every time a tab is selected, so state held inside the screen
/// was thrown away on every switch).
///
/// What is kept:
///  * the selected opponent, game filter and whether a report was generated
///    (so the same report is still showing when they come back);
///  * the computed [ScoutingReportData] + [ScoutingSheet].
///
/// When it is rebuilt: only when the data the report is built from actually
/// changed. [resolve] fingerprints the report's own rows and the full history
/// rows it scores against, so logging a pitch, editing a row, deleting a game,
/// or changing the season filter all produce a new fingerprint and a fresh
/// report, while merely switching tabs (or any unrelated rebuild) reuses the
/// existing one. Nothing is cached by time, so it can never go stale.
class ScoutingReportCache {
  String? team;
  String gameNum = 'All';
  bool generated = false;

  int? _fingerprint;
  String? _forTeam;
  ScoutingReportData? _data;
  ScoutingSheet? _sheet;

  /// Forgets everything (sign-out, switching pitcher).
  void reset() {
    team = null;
    gameNum = 'All';
    generated = false;
    _invalidate();
  }

  void _invalidate() {
    _fingerprint = null;
    _forTeam = null;
    _data = null;
    _sheet = null;
  }

  /// Order-sensitive fingerprint over every field a report can depend on.
  static int _fingerprintOf(String forTeam, List<PitchEvent> data, List<PitchEvent> history) {
    int row(PitchEvent e) => Object.hash(
          e.id,
          e.game,
          e.gameNumber,
          e.season,
          e.batter,
          e.batterNumber,
          e.battingOrder,
          e.hand,
          e.eventType,
          e.pitchNum,
          e.pitchType,
          e.call,
          Object.hash(e.outcome, e.ab, e.outs, e.er, e.xCoord, e.yCoord, e.battedType, e.inning, e.paId),
        );
    return Object.hash(
      forTeam,
      data.length,
      Object.hashAll(data.map(row)),
      history.length,
      Object.hashAll(history.map(row)),
    );
  }

  /// The report for [forTeam] built from [data] (already filtered to that team
  /// and game) and [history] (the season-filtered pitches used for scoring).
  /// Reuses the stored one when nothing it depends on has changed.
  ({ScoutingReportData report, ScoutingSheet sheet}) resolve(
    String forTeam,
    List<PitchEvent> data,
    List<PitchEvent> history,
  ) {
    final fp = _fingerprintOf(forTeam, data, history);
    if (_data == null || _sheet == null || _fingerprint != fp || _forTeam != forTeam) {
      final r = ScoutingReportData.compute(forTeam, data, history: history);
      _data = r;
      _sheet = ScoutingSheet.build(r);
      _fingerprint = fp;
      _forTeam = forTeam;
    }
    return (report: _data!, sheet: _sheet!);
  }
}

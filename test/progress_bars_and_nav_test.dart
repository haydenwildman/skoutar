// Progress-bar direction / scale rules and the removed Admin Panel.
//
// Run with:  flutter test test/progress_bars_and_nav_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';
import 'package:pitching_analytics/widgets/sidebar_nav.dart';
import 'package:pitching_analytics/widgets/stat_vbox.dart';
import 'package:pitching_analytics/widgets/tier_scale_bar.dart';
import 'package:pitching_analytics/widgets/value_bar.dart';

const _lowerIsBetter = <String>[
  'ERA', 'WHIP', 'BB_pct', 'AVG', 'OBP_allowed', 'SLG', 'PPA', 'ball_pct',
  'contact_pct', 'fb_pct', 'ld_pct', 'usage_predictability',
  'batter_AVG', 'batter_OBP', 'batter_SLG', 'batter_OPS', 'batter_BB_pct', 'batter_BABIP',
];
const _higherIsBetter = <String>[
  'K_pct', 'whiff_pct', 'f_strike', 'kbb_pct', 'chase_pct', 'gb_pct', 'seq_score', 'batter_K_pct',
];

/// A stat's full-scale value, recovered through the public API.
double _scaleMax(String stat) => 0.01 / statValueFraction(stat, 0.01)!;

void main() {
  group('direction', () {
    test('lower-is-better stats are flagged lower-is-better', () {
      for (final s in _lowerIsBetter) {
        expect(statLowerIsBetter(s), isTrue, reason: s);
      }
    });
    test('higher-is-better stats are not', () {
      for (final s in _higherIsBetter) {
        expect(statLowerIsBetter(s), isFalse, reason: s);
      }
    });

    test('ERA: green on the left, red on the right', () {
      final c = statTierColorsLeftToRight('ERA');
      expect(c.first, AppColors.perfExcellent);
      expect(c.last, AppColors.perfPoor);
    });
    test('K%: red on the left, green on the right', () {
      final c = statTierColorsLeftToRight('K_pct');
      expect(c.first, AppColors.perfPoor);
      expect(c.last, AppColors.perfExcellent);
    });

    test('the bands behind the marker always match the tier color perfHex gives', () {
      for (final stat in [..._lowerIsBetter, ..._higherIsBetter]) {
        final colors = statTierColorsLeftToRight(stat);
        final cuts = statTierCutoffFractions(stat);
        final max = _scaleMax(stat);
        for (var i = 0; i < 5; i++) {
          final lo = i == 0 ? 0.0 : cuts[i - 1];
          final hi = i == 4 ? 1.0 : cuts[i];
          if (hi - lo < 1e-6) continue;
          final value = (lo + hi) / 2 * max;
          expect(perfHex(stat, value), colors[i], reason: '$stat band $i @ $value');
        }
      }
    });
  });

  group('scale', () {
    test('marker position is the real value on a 0..max scale', () {
      expect(statValueFraction('ERA', 5.0), closeTo(0.5, 1e-9));
      expect(statValueFraction('ERA', 12.0), 1.0); // 10.00+ pins to the end
      expect(statValueFraction('ERA', 0.0), 0.0);
      expect(statValueFraction('AVG', 0.250), closeTo(0.5, 1e-9));
    });
    test('every percentage stat runs 0-100%', () {
      for (final s in [
        'K_pct', 'BB_pct', 'whiff_pct', 'f_strike', 'kbb_pct', 'chase_pct', 'contact_pct',
        'gb_pct', 'fb_pct', 'ld_pct', 'ball_pct', 'batter_BB_pct', 'batter_K_pct',
      ]) {
        expect(statValueFraction(s, 25), closeTo(0.25, 1e-9), reason: s);
        expect(statValueFraction(s, 100), 1.0, reason: s);
      }
    });
    test('missing values / unknown stats have no marker', () {
      expect(statValueFraction('ERA', null), isNull);
      expect(statValueFraction('nope', 3), isNull);
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester t, double w, Widget child) async {
      t.view.physicalSize = Size(w, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: child)),
      ));
      await t.pumpAndSettle();
    }

    for (final w in <double>[1440, 768, 430, 320]) {
      testWidgets('tier bars render without layout errors at ${w.toInt()}px', (t) async {
        await pump(
          t,
          w,
          Column(children: const [
            TierScaleBar(statKey: 'ERA', rawValue: 0.0, valueText: '0.00'),
            SizedBox(height: 8),
            TierScaleBar(statKey: 'ERA', rawValue: 14.5, valueText: '14.50'),
            SizedBox(height: 8),
            TierScaleBar(statKey: 'K_pct', rawValue: 100, valueText: '100%'),
            SizedBox(height: 8),
            TierScaleBar(statKey: 'whiff_pct', rawValue: 25, valueText: '25%'),
            SizedBox(height: 8),
            TierScaleBar(statKey: 'AVG', rawValue: null, valueText: 'N/A'),
            SizedBox(height: 8),
            TierScaleBar(statKey: 'WHIP', rawValue: 1.31, valueText: '1.31', compact: true),
            SizedBox(height: 8),
            ValueBar(fraction: 0.25, color: AppColors.perfGood, text: '25%'),
            SizedBox(height: 8),
            ValueBar(fraction: 0.02, color: AppColors.perfGood, text: '2%'),
          ]),
        );
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('ValueBar fill is exactly the fraction of the track', (t) async {
      await pump(t, 800, const ValueBar(fraction: 0.25, color: AppColors.perfGood, text: '25%'));
      final track = t.getRect(find.byType(ValueBar));
      final fill = t.getSize(find.descendant(
        of: find.byType(ValueBar),
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.height == 26 && w.width != double.infinity),
      ));
      expect(fill.width, closeTo(track.width * 0.25, 1.0));
    });

    testWidgets('PerfStatBar draws a tier bar for graded stats', (t) async {
      await pump(
        t,
        430,
        const PerfStatBar(label: 'ERA', value: '3.62', color: AppColors.perfAverage, statKey: 'ERA', rawValue: 3.62),
      );
      expect(find.byType(TierScaleBar), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    for (final w in <double>[1440, 768, 430, 320]) {
      testWidgets('PerfStatBar puts the real value in a large header row at ${w.toInt()}px', (t) async {
        await pump(
          t,
          w,
          Column(children: const [
            PerfStatBar(label: 'ERA', value: '3.62', color: AppColors.perfAverage, statKey: 'ERA', rawValue: 3.62),
            PerfStatBar(label: 'Two-Strike Count %', value: '54.3%', color: AppColors.perfGood, statKey: 'f_strike', rawValue: 54.3),
            PerfStatBar(label: 'AVG Against', value: 'N/A', color: AppColors.colBorder),
            PerfStatBar(label: 'IP', value: '12.1', color: AppColors.tint),
            StatSummaryCard(label: 'SLG Against', value: '.412', statKey: 'SLG', rawValue: 0.412),
          ]),
        );
        expect(t.takeException(), isNull);
        // The actual statistic is its own Text, sized as a primary number
        // (>= 22px on phones, 28px on desktop) - not text on the bar.
        final era = t.widget<Text>(find.text('3.62'));
        expect(era.style!.fontSize, greaterThanOrEqualTo(22));
        expect(era.style!.fontWeight, FontWeight.w900);
        // The value sits on the same row as its label and above the bar.
        expect(t.getTopLeft(find.text('3.62')).dy, lessThan(t.getTopLeft(find.byType(TierScaleBar).first).dy));
        expect(find.text('.412'), findsOneWidget);
      });
    }

    testWidgets('statValueFontSize steps down for narrower screens', (t) async {
      late double desktop, tablet, phone;
      Future<void> at(double w, void Function(double) set) async {
        t.view.physicalSize = Size(w, 900);
        t.view.devicePixelRatio = 1.0;
        await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
          set(statValueFontSize(c));
          return const SizedBox();
        })));
      }
      await at(1440, (v) => desktop = v);
      await at(768, (v) => tablet = v);
      await at(390, (v) => phone = v);
      addTearDown(t.view.resetPhysicalSize);
      expect(desktop, 28);
      expect(tablet, lessThan(desktop));
      expect(phone, lessThan(tablet));
    });
  });

  group('navigation', () {
    testWidgets('there is no Admin Panel entry', (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(children: [
            SidebarNav(
              selected: 'Game Input',
              onSelect: (_) {},
              isPlus: true,
              pitcherName: 'Test',
              onLogout: () {},
              onToggleCollapse: () {},
            ),
          ]),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Admin Panel'), findsNothing);
      expect(find.text('ADMIN'), findsNothing);
      expect(find.text('Game Input'), findsWidgets);
      expect(t.takeException(), isNull);
      expect(mainNavItems.any((i) => i.label == 'Admin Panel'), isFalse);
    });
  });
}

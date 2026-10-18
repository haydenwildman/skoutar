// Pitcher profiles + plan limits (pure logic, no network).
// Run with:  flutter test test/pitcher_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitcher.dart';
import 'package:pitching_analytics/models/subscription_plan.dart';

void main() {
  group('PitcherDraft.validate', () {
    PitcherDraft ok() => PitcherDraft(
        name: 'Jake Miller', username: 'jmiller22', sports: {'baseball'}, hand: 'R');

    test('accepts a complete draft', () => expect(ok().validate(), isNull));

    test('requires name, username, sport and hand', () {
      expect((ok()..name = ' ').validate(), isNotNull);
      expect((ok()..username = 'a!').validate(), isNotNull);
      expect((ok()..sports.clear()).validate(), isNotNull);
      expect((ok()..hand = null).validate(), isNotNull);
    });

    test('both sports are allowed', () {
      expect((ok()..sports.add('softball')).validate(), isNull);
      expect(ok().toJson()['sports'], ['baseball']);
    });
  });

  group('Pitcher', () {
    test('profile is incomplete without throwing hand or sport', () {
      const base = Pitcher(id: 'a', ownerId: 'a', displayName: 'A', username: 'aaa');
      expect(base.isComplete, isFalse);
      const full = Pitcher(
          id: 'a', ownerId: 'a', displayName: 'A', username: 'aaa',
          sports: ['softball'], throwsHand: 'L');
      expect(full.isComplete, isTrue);
      expect(full.handLabel, 'Left-handed');
    });
  });

  group('plan limits', () {
    test('Individual 1, Family 4, Team 20 - and no feature differences are modelled', () {
      final limits = {for (final p in SubscriptionPlan.fallback) p.id: p.pitcherLimit};
      expect(limits, {'individual': 1, 'family': 4, 'team': 20});
    });

    test('plans read the pitcher limit from the database row', () {
      final p = SubscriptionPlan.fromMap({
        'id': 'family',
        'name': 'Family',
        'monthly_price_cents': 1499,
        'max_pitchers': 4,
        'features': ['x'],
      });
      expect(p.pitcherLimit, 4);
      expect(p.priceLabel, '\$14.99 / month');
    });
  });
}

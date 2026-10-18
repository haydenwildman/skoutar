import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitcher_profile.dart';
import 'package:pitching_analytics/models/subscription_plan.dart';
import 'package:pitching_analytics/models/user.dart';
import 'package:pitching_analytics/widgets/pitcher_form.dart';

void main() {
  test('fallback plans: 1 / 3 / 20 pitchers, no feature restrictions', () {
    final byId = {for (final p in SubscriptionPlan.fallback) p.id: p};
    expect(byId['individual']!.maxPitchers, 1);
    expect(byId['family']!.maxPitchers, 3);
    expect(byId['team']!.maxPitchers, 20);
    expect(byId.containsKey('basic'), isFalse);
  });

  test('a plan row with no limit set falls back to the plan defaults', () {
    const team = SubscriptionPlan(id: 'team', name: 'Team', monthlyPriceCents: 1999);
    expect(team.maxPitchers, 20);
  });

  test('nothing is locked for any tier', () {
    for (final t in UserTier.values) {
      expect(AppUser(id: 'x', username: 'u', email: 'e@x.co', tier: t).isPlus, isTrue);
    }
  });

  test('pitcher form validation', () {
    final d = PitcherFormData();
    expect(d.validate(), isNotNull); // empty
    d.nameCtrl.text = 'Sam Lee';
    d.userCtrl.text = 'sam_lee';
    expect(d.validate(), isNotNull); // no sport / hand yet
    d.sports.add('baseball');
    d.hand = 'L';
    expect(d.validate(), isNull);
    d.userCtrl.text = 'no spaces!';
    expect(d.validate(), isNotNull);
    d.dispose();
  });

  test('profile completeness drives the "complete your profile" prompt', () {
    const incomplete = PitcherProfile(id: '1', displayName: 'A', username: 'aaa');
    const complete = PitcherProfile(
        id: '2', displayName: 'B', username: 'bbb', sports: ['baseball'], throwsHand: 'R');
    expect(incomplete.isComplete, isFalse);
    expect(complete.isComplete, isTrue);
  });
}

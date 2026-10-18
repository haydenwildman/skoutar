import '../models/subscription_plan.dart';
import 'supabase_config.dart';

/// Loads the plans shown on the sign-up screen (public, read-only table).
class PlanService {
  /// [fromServer] is false when the fallback list is shown (database
  /// unreachable or migration not run yet).
  Future<({List<SubscriptionPlan> plans, bool fromServer})> fetchPlans() async {
    try {
      final rows = await sb
          .from('subscription_plans')
          .select()
          .eq('active', true)
          .order('sort_order');
      final plans = (rows as List)
          .map((r) => SubscriptionPlan.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      if (plans.isNotEmpty) return (plans: plans, fromServer: true);
    } catch (_) {
      // fall through to the display-only fallback
    }
    return (plans: SubscriptionPlan.fallback, fromServer: false);
  }
}

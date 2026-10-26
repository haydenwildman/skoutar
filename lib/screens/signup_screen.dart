import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pitcher.dart';
import '../models/subscription_plan.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/legal_config.dart';
import '../services/plan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_shell.dart';
import '../widgets/orange_glow_button.dart';
import '../widgets/password_field.dart';
import '../widgets/pitcher_form.dart';
import '../widgets/skoutar_logo.dart';
import '../widgets/stat_hold_info.dart';

/// Guided registration:
///   Plan -> Account (owner email + password) -> Pitcher -> [More pitchers] -> Review
/// "More pitchers" only appears for plans that allow more than one pitcher.
/// One login (the account owner) covers every pitcher; each pitcher's data is
/// stored separately. Choosing a plan only records which plan was picked:
/// it never grants anything paid and no payment is taken.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  int _step = 0;
  SubscriptionPlan? _plan;
  final List<PitcherDraft> _pitchers = [PitcherDraft()]; // [0] = first pitcher
  bool _agreed = false;

  List<SubscriptionPlan> _plans = [];
  bool _plansLoading = true;
  bool _plansFromServer = true;

  String? _message;
  bool _success = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    final r = await PlanService().fetchPlans();
    if (!mounted) return;
    setState(() {
      _plans = r.plans;
      _plansFromServer = r.fromServer;
      _plansLoading = false;
    });
  }

  int get _limit => _plan?.pitcherLimit ?? 1;
  bool get _multi => _limit > 1;

  List<String> get _steps => [
        'Plan',
        'Account',
        'Pitcher',
        if (_multi) 'More pitchers',
        'Review',
      ];

  String get _stepName => _steps[_step.clamp(0, _steps.length - 1)];

  void _choosePlan(SubscriptionPlan p) {
    setState(() {
      _plan = p;
      // a smaller plan can't keep extra pitchers
      if (_pitchers.length > p.pitcherLimit) {
        _pitchers.removeRange(p.pitcherLimit, _pitchers.length);
      }
    });
  }

  void _fail(String msg) => setState(() {
        _message = msg;
        _success = false;
      });

  bool _usernameTaken(String u, {PitcherDraft? except}) {
    final key = u.trim().toLowerCase();
    return _pitchers.any((d) => !identical(d, except) && d.username.trim().toLowerCase() == key);
  }

  Future<void> _next() async {
    setState(() => _message = null);
    switch (_stepName) {
      case 'Plan':
        if (_plan == null) return _fail('Choose a plan to continue.');
        setState(() => _step++);
      case 'Account':
        if (!AuthService.isValidEmail(_emailCtrl.text)) {
          return _fail('Enter a valid email address.');
        }
        final pErr = AuthService.validatePassword(_passCtrl.text);
        if (pErr != null) return _fail(pErr);
        if (_passCtrl.text != _pass2Ctrl.text) return _fail('Passwords do not match.');
        setState(() => _step++);
      case 'Pitcher':
        final err = _pitchers.first.validate();
        if (err != null) return _fail(err);
        setState(() => _step++);
      case 'More pitchers':
        setState(() => _step++);
      default:
        await _submit();
    }
  }

  void _back() {
    setState(() {
      _message = null;
      _step -= 1;
    });
  }

  Future<void> _submit() async {
    if (_plan == null) return _fail('Choose a plan to continue.');
    if (!_agreed) {
      return _fail('Please agree to the Terms of Service and Privacy Policy.');
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await context.read<AppSession>().auth.signUp(
          email: _emailCtrl.text,
          password: _passCtrl.text,
          confirmPassword: _pass2Ctrl.text,
          pitchers: _pitchers,
          planId: _plan!.id,
          pitcherLimit: _limit,
          termsVersion: LegalConfig.termsVersion,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = result.message;
      _success = result.success;
    });
  }

  Future<void> _openLink(String url, String name) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The $name link has not been published yet.')),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _addOrEditExtra({PitcherDraft? existing}) async {
    await showPitcherEditor(
      context,
      title: existing == null ? 'Add Pitcher' : 'Edit Pitcher',
      submitLabel: existing == null ? 'Add Pitcher' : 'Save',
      initial: existing,
      onSubmit: (d) async {
        if (_usernameTaken(d.username, except: existing)) {
          return 'Another pitcher here already uses that username.';
        }
        setState(() {
          if (existing == null) {
            if (_pitchers.length < _limit) _pitchers.add(d);
          } else {
            final i = _pitchers.indexWhere((x) => identical(x, existing));
            if (i >= 0) _pitchers[i] = d;
          }
        });
        return null;
      },
    );
  }

  // ── UI pieces ────────────────────────────────────────────────
  Widget _stepper() {
    final names = _steps;
    return Row(
      children: [
        for (var i = 0; i < names.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? AppColors.brandOrange : AppColors.colBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${i + 1}. ${names[i]}',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == _step ? FontWeight.w900 : FontWeight.w600,
                    color: i == _step ? AppColors.ink : AppColors.colMuted,
                  ),
                ),
              ],
            ),
          ),
          if (i < names.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _planCard(SubscriptionPlan p) {
    final selected = _plan?.id == p.id;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _choosePlan(p),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 2),
          borderRadius: BorderRadius.circular(10),
          color: selected ? AppColors.tint : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: selected ? AppColors.brandOrangeDeep : AppColors.colMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink)),
                ),
                Text(p.priceLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.brandOrangeDeep)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.pitcherLimit == 1
                  ? '1 pitcher profile'
                  : 'Up to ${p.pitcherLimit} pitcher profiles',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            Text(p.trialLabel,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.perfExcellent)),
            const SizedBox(height: 6),
            for (final f in p.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check, size: 14, color: AppColors.brandOrangeDeep),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trialNotice() {
    final p = _plan;
    final trial = p == null
        ? 'Every plan includes a free trial.'
        : p.hasTrialLength
            ? '${p.name} includes a ${p.trialDays}-day free trial, then ${p.priceLabel}.'
            : '${p.name} includes a free trial (length to be announced), then ${p.priceLabel}.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About your free trial',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 4),
          Text(trial, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          const Text(
            'You will not be charged to create an account, and no payment details '
            'are collected now. Billing is not active yet. Before any charge, '
            'SKOUTAR will show you the recurring price, when billing begins, and '
            'how to cancel.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _planStep() => [
        const Text('Choose your plan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 2),
        const Text('Every plan includes every SKOUTAR feature. Plans differ only by how many pitchers they cover.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
        const SizedBox(height: 8),
        if (_plansLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (!_plansFromServer)
            const AuthMessage(
              text: 'Plan details could not be loaded from the server, so default '
                  'plans are shown. Sign-up may not work until this is fixed.',
            ),
          for (final p in _plans) _planCard(p),
        ],
        _trialNotice(),
      ];

  List<Widget> _accountStep() => [
        const Text('Account owner',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 2),
        const Text('This one login manages the subscription and every pitcher on the account.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
        const SizedBox(height: 10),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
        ),
        const SizedBox(height: 10),
        PasswordField(controller: _passCtrl, textInputAction: TextInputAction.next),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Text(
            'At least ${LegalConfig.minPasswordLength} characters, with a letter and a number.',
            style: TextStyle(fontSize: 11, color: AppColors.colMuted),
          ),
        ),
        const SizedBox(height: 10),
        PasswordField(
          controller: _pass2Ctrl,
          label: 'Confirm Password',
          onSubmitted: (_) => _loading ? null : _next(),
        ),
      ];

  List<Widget> _pitcherStep() => [
        Text(_multi ? 'First pitcher' : 'Your pitcher profile',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          _multi
              ? 'Add the first pitcher now. You can add the others next.'
              : 'This profile is created for you automatically.',
          style: const TextStyle(fontSize: 12, color: AppColors.colMuted),
        ),
        const SizedBox(height: 10),
        PitcherFormFields(draft: _pitchers.first),
      ];

  Widget _pitcherRow(PitcherDraft d, {required bool removable}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.colBorder, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  '@${d.username.trim()} · '
                  '${(d.sports.toList()..sort()).map((s) => s == 'baseball' ? 'Baseball' : 'Softball').join(' & ')} · '
                  '${d.hand == 'L' ? 'Left-handed' : 'Right-handed'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.colMuted),
                ),
              ],
            ),
          ),
          if (removable) ...[
            HoldTip(message: 'Edit', child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _addOrEditExtra(existing: d),
            )),
            HoldTip(message: 'Remove', child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _pitchers.remove(d)),
            )),
          ],
        ],
      ),
    );
  }

  List<Widget> _morePitchersStep() => [
        Text('Pitchers on this account: ${_pitchers.length} of $_limit',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 2),
        const Text(
          'Everyone shares this login and picks their name from a list. Each pitcher\'s '
          'stats are saved separately. You can also add pitchers later.',
          style: TextStyle(fontSize: 12, color: AppColors.colMuted),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _pitchers.length; i++) _pitcherRow(_pitchers[i], removable: i > 0),
        const SizedBox(height: 4),
        if (_pitchers.length < _limit)
          OutlinedButton.icon(
            onPressed: () => _addOrEditExtra(),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add Pitcher'),
          )
        else
          Text('Your plan is full ($_limit pitchers).',
              style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
      ];

  List<Widget> _reviewStep() => [
        const Text('Review',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        Text('${_plan?.name ?? ''} plan · ${_plan?.priceLabel ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('Owner login: ${_emailCtrl.text.trim()}',
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        for (final d in _pitchers) _pitcherRow(d, removable: false),
        const SizedBox(height: 4),
        _trialNotice(),
        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('I agree to the Terms of Service and Privacy Policy.',
              style: TextStyle(fontSize: 13)),
        ),
        Row(
          children: [
            TextButton(
              onPressed: () => _openLink(LegalConfig.termsUrl, 'Terms of Service'),
              child: const Text('Terms of Service'),
            ),
            TextButton(
              onPressed: () => _openLink(LegalConfig.privacyUrl, 'Privacy Policy'),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return AuthShell(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkoutarLogo(height: 88),
            const SizedBox(height: 12),
            AuthMessage(text: _message ?? 'Account created!', success: true),
            SizedBox(
              width: double.infinity,
              child: OrangeGlowButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Login'),
              ),
            ),
          ],
        ),
      );
    }

    final name = _stepName;
    final isLast = name == 'Review';
    return AuthShell(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: SkoutarLogo(height: 80)),
          const SizedBox(height: 8),
          const Center(
            child: Text('Create Account',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink)),
          ),
          if (_plan != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${_plan!.name} · ${_plan!.priceLabel} · '
                  '${_limit == 1 ? '1 pitcher' : 'up to $_limit pitchers'}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandOrangeDeep),
                ),
              ),
            ),
          const SizedBox(height: 14),
          _stepper(),
          const SizedBox(height: 16),
          if (_message != null) AuthMessage(text: _message!, success: _success),
          if (name == 'Plan') ..._planStep(),
          if (name == 'Account') ..._accountStep(),
          if (name == 'Pitcher') ..._pitcherStep(),
          if (name == 'More pitchers') ..._morePitchersStep(),
          if (name == 'Review') ..._reviewStep(),
          const SizedBox(height: 16),
          OrangeGlowButton(
            onPressed: (_loading || (name == 'Plan' && _plansLoading)) ? null : _next,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandOrangeDeep))
                : Text(isLast ? 'Create Account →' : 'Continue →'),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : (_step == 0 ? () => Navigator.of(context).pop() : _back),
              child: Text(_step == 0 ? '← Back to Login' : '← Back'),
            ),
          ),
          if (_step > 0)
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('Back to Login'),
              ),
            ),
        ],
      ),
    );
  }
}

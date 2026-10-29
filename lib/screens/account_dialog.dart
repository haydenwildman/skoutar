import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_shell.dart';
import 'subscribe_screen.dart';
import 'login_screen.dart';

/// Account summary + permanent account deletion. Opened by tapping the
/// pitcher-name chip in the sidebar.
Future<void> showAccountDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _AccountDialog());
}

class _AccountDialog extends StatelessWidget {
  const _AccountDialog();

  String _planLabel(AppUser u) {
    if (u.planName == null) return 'No plan selected';
    final status = switch (u.subscriptionStatus) {
      'trialing' => u.trialEnd != null
          ? 'free trial until ${u.trialEnd!.month}/${u.trialEnd!.day}/${u.trialEnd!.year}'
          : 'free trial',
      'pending' => 'billing not active yet',
      'active' => 'active',
      'past_due' => 'payment past due',
      'canceled' => 'canceled',
      'expired' => 'expired',
      _ => '',
    };
    return status.isEmpty ? u.planName! : '${u.planName} ($status)';
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(k,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.colMuted)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppSession>().currentUser;
    if (user == null) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Your account'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Email', user.email),
            _row('Plan', _planLabel(user)),
            _row('Pitchers',
                '${context.watch<AppSession>().pitchers.length} of ${user.maxPitchers}'),
            const Divider(height: 28),
            const Text('Delete account',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Permanently deletes your login, EVERY pitcher profile on this account, and all of '
              'their pitching data. This cannot be undone.',
              style: TextStyle(fontSize: 12, color: AppColors.colMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => const SubscribeScreen()));
          },
          child: const Text('Subscription'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.colError),
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => const _ConfirmDeleteDialog(),
            );
          },
          child: const Text('Delete account…'),
        ),
      ],
    );
  }
}

class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog();

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<AppSession>();
    final nav = Navigator.of(context, rootNavigator: true);
    final res = await session.auth.deleteAccount();
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _loading = false;
        _error = res.message;
      });
      return;
    }
    try {
      await session.logout(); // clears local data held in memory
    } catch (_) {}
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.text.trim() == 'DELETE';
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The login and every pitcher\'s data will be permanently deleted. '
                'Type DELETE to confirm.'),
            const SizedBox(height: 12),
            if (_error != null) AuthMessage(text: _error!),
            TextField(
              controller: _ctrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Type DELETE'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.colError),
          onPressed: (!ready || _loading) ? null : _delete,
          child: _loading
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete permanently'),
        ),
      ],
    );
  }
}

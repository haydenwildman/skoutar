import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pitcher.dart';
import '../services/app_session.dart';
import '../services/pitcher_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_shell.dart';
import '../widgets/pitcher_form.dart';
import 'account_dialog.dart';
import '../widgets/stat_hold_info.dart';

/// Opened from the sidebar name chip: pick which pitcher is active, add a
/// pitcher (if the plan has room), edit or remove pitchers.
Future<void> showPitcherSwitcher(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _SwitcherDialog());
}

/// Edit dialog for one pitcher (also used by the Bullpen "complete profile" prompt).
Future<void> showEditPitcher(BuildContext context, Pitcher p) async {
  final session = context.read<AppSession>();
  final saved = await showPitcherEditor(
    context,
    title: 'Edit ${p.displayName}',
    submitLabel: 'Save',
    initial: PitcherDraft.from(p),
    onSubmit: (d) async {
      try {
        await session.pitcherService.updatePitcher(p.id, d);
        await session.refreshPitchers();
        return null;
      } catch (e) {
        return PitcherService.friendlyError(e);
      }
    },
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
  }
}

class _SwitcherDialog extends StatelessWidget {
  const _SwitcherDialog();

  Future<void> _select(BuildContext context, Pitcher p) async {
    final session = context.read<AppSession>();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (p.id == session.activePitcher?.id) return;
    try {
      await session.switchPitcher(p);
      messenger.showSnackBar(SnackBar(content: Text('Now viewing ${p.displayName}')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not load that pitcher. Please try again.')));
    }
  }

  Future<void> _add(BuildContext context) async {
    final session = context.read<AppSession>();
    await showPitcherEditor(
      context,
      title: 'Add Pitcher',
      submitLabel: 'Add Pitcher',
      onSubmit: (d) async {
        try {
          await session.pitcherService.addPitcher(d);
          await session.refreshPitchers();
          return null;
        } catch (e) {
          return PitcherService.friendlyError(e);
        }
      },
    );
  }

  Future<void> _remove(BuildContext context, Pitcher p) async {
    final session = context.read<AppSession>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.displayName}?'),
        content: const Text(
            'This pitcher is hidden from the list and no longer counts toward your plan. '
            'Their data is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.colError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final wasActive = p.id == session.activePitcher?.id;
      await session.pitcherService.archivePitcher(p.id);
      await session.refreshPitchers(keepActive: !wasActive);
      if (wasActive && session.activePitcher != null) {
        // the removed pitcher was on screen: load the new active pitcher's data
        final next = session.activePitcher!;
        session.activePitcher = null;
        await session.switchPitcher(next);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(PitcherService.friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final user = session.currentUser;
    final planName = user?.planName ?? 'Your plan';
    return AlertDialog(
      title: const Text('Pitchers'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$planName: ${session.pitchers.length} of ${session.pitcherLimit} pitcher'
              '${session.pitcherLimit == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: AppColors.colMuted),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final p in session.pitchers)
                      _PitcherTile(
                        pitcher: p,
                        active: p.id == session.activePitcher?.id,
                        canRemove: session.pitchers.length > 1,
                        onSelect: () => _select(context, p),
                        onEdit: () => showEditPitcher(context, p),
                        onRemove: () => _remove(context, p),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (session.canAddPitcher)
              OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Add Pitcher'),
              )
            else if (session.pitcherLimit > 1)
              const Text('Your plan is full. Remove a pitcher to add another.',
                  style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            showAccountDialog(context);
          },
          child: const Text('Account…'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _PitcherTile extends StatelessWidget {
  final Pitcher pitcher;
  final bool active;
  final bool canRemove;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  const _PitcherTile({
    required this.pitcher,
    required this.active,
    required this.canRemove,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(
            color: active ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 2),
        borderRadius: BorderRadius.circular(10),
        color: active ? AppColors.tint : Colors.white,
      ),
      child: ListTile(
        dense: true,
        onTap: onSelect,
        leading: Icon(active ? Icons.radio_button_checked : Icons.radio_button_off,
            color: active ? AppColors.brandOrangeDeep : AppColors.colMuted),
        title: Text(pitcher.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          pitcher.isComplete
              ? '${pitcher.sportLabel} · ${pitcher.handLabel}'
              : 'Profile incomplete — tap ⋮ to edit',
          style: TextStyle(
              fontSize: 12,
              color: pitcher.isComplete ? AppColors.colMuted : AppColors.colError),
        ),
        trailing: HoldTip(message: 'Pitcher options', child: PopupMenuButton<String>(
          tooltip: '', // no hover tooltip; the HoldTip above explains it on press-and-hold
          onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit profile')),
            if (canRemove) const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        )),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/pitcher.dart';
import '../theme/app_theme.dart';
import 'auth_shell.dart';
import 'orange_glow_button.dart';

/// Name / username / sport / throwing-hand fields for one pitcher. Edits the
/// given [draft] in place and calls [onChanged].
class PitcherFormFields extends StatefulWidget {
  final PitcherDraft draft;
  final VoidCallback? onChanged;
  const PitcherFormFields({super.key, required this.draft, this.onChanged});

  @override
  State<PitcherFormFields> createState() => _PitcherFormFieldsState();
}

class _PitcherFormFieldsState extends State<PitcherFormFields> {
  late final TextEditingController _name = TextEditingController(text: widget.draft.name);
  late final TextEditingController _user = TextEditingController(text: widget.draft.username);

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    super.dispose();
  }

  void _changed() {
    widget.draft.name = _name.text;
    widget.draft.username = _user.text;
    widget.onChanged?.call();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.tint,
      backgroundColor: Colors.white,
      showCheckmark: false,
      avatar: selected
          ? const Icon(Icons.check, size: 16, color: AppColors.brandOrangeDeep)
          : null,
      side: BorderSide(
        color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder,
        width: 2,
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          onChanged: (_) => _changed(),
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Pitcher name', hintText: 'e.g. Jake Miller'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _user,
          onChanged: (_) => _changed(),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'e.g. jmiller22',
            helperText: '3-20 letters, numbers or underscores',
          ),
        ),
        const SizedBox(height: 14),
        const Text('Sport', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const Text('Select both if this pitcher plays both.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in const ['baseball', 'softball'])
            _chip(s == 'baseball' ? 'Baseball' : 'Softball', d.sports.contains(s), () {
              setState(() => d.sports.contains(s) ? d.sports.remove(s) : d.sports.add(s));
              widget.onChanged?.call();
            }),
        ]),
        const SizedBox(height: 14),
        const Text('Throwing hand', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip('Right-handed', d.hand == 'R', () {
            setState(() => d.hand = 'R');
            widget.onChanged?.call();
          }),
          _chip('Left-handed', d.hand == 'L', () {
            setState(() => d.hand = 'L');
            widget.onChanged?.call();
          }),
        ]),
      ],
    );
  }
}

/// Add / edit dialog. [onSubmit] receives the validated draft and returns an
/// error message to show (dialog stays open) or null on success (dialog closes).
Future<bool> showPitcherEditor(
  BuildContext context, {
  required String title,
  required String submitLabel,
  PitcherDraft? initial,
  required Future<String?> Function(PitcherDraft draft) onSubmit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PitcherEditorDialog(
      title: title,
      submitLabel: submitLabel,
      draft: initial?.copy() ?? PitcherDraft(),
      onSubmit: onSubmit,
    ),
  );
  return ok ?? false;
}

class _PitcherEditorDialog extends StatefulWidget {
  final String title;
  final String submitLabel;
  final PitcherDraft draft;
  final Future<String?> Function(PitcherDraft) onSubmit;
  const _PitcherEditorDialog({
    required this.title,
    required this.submitLabel,
    required this.draft,
    required this.onSubmit,
  });

  @override
  State<_PitcherEditorDialog> createState() => _PitcherEditorDialogState();
}

class _PitcherEditorDialogState extends State<_PitcherEditorDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final err = widget.draft.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final serverErr = await widget.onSubmit(widget.draft);
    if (!mounted) return;
    if (serverErr == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = serverErr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) AuthMessage(text: _error!),
              PitcherFormFields(draft: widget.draft),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        SizedBox(
          width: 150,
          child: OrangeGlowButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandOrangeDeep))
                : Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}

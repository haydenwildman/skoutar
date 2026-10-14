import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<AppUser> _users = [];
  bool _loading = true;

  final _newUserCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  UserTier _newTier = UserTier.basic;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final session = context.read<AppSession>();
    final users = await session.auth.allUsers();
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _createUser() async {
    final session = context.read<AppSession>();
    if (_newUserCtrl.text.trim().isEmpty || _newPassCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Username and password required.')));
      return;
    }
    try {
      await session.auth.adminCreateUser(
        username: _newUserCtrl.text,
        email: _newEmailCtrl.text,
        password: _newPassCtrl.text,
        tier: _newTier,
      );
      _newUserCtrl.clear();
      _newEmailCtrl.clear();
      _newPassCtrl.clear();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ User created.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteUser(AppUser u) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Permanently delete "${u.username}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await context.read<AppSession>().auth.adminDeleteUser(u.id);
    await _refresh();
  }

  Future<void> _resetPassword(AppUser u) async {
    final ctrl = TextEditingController();
    final newPass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset password — ${u.username}'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Reset')),
        ],
      ),
    );
    if (newPass == null || newPass.length < 6) return;
    await context.read<AppSession>().auth.adminResetPassword(u.id, newPass);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ Password reset.')));
    }
  }

  Future<void> _changeTier(AppUser u, UserTier tier) async {
    await context.read<AppSession>().auth.adminUpdateUser(u.id, tier: tier);
    await _refresh();
  }

  Future<void> _changeStatus(AppUser u, SubStatus status) async {
    await context.read<AppSession>().auth.adminUpdateUser(u.id, status: status);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👥 User Management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(AppColors.blueDark),
                    headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    columns: const [
                      DataColumn(label: Text('Username')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Tier')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final u in _users)
                        DataRow(cells: [
                          DataCell(Text(u.username)),
                          DataCell(Text(u.email)),
                          DataCell(DropdownButton<UserTier>(
                            value: u.tier,
                            underline: const SizedBox(),
                            items: UserTier.values
                                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                                .toList(),
                            onChanged: (v) => v == null ? null : _changeTier(u, v),
                          )),
                          DataCell(DropdownButton<SubStatus>(
                            value: u.status,
                            underline: const SizedBox(),
                            items: SubStatus.values
                                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                                .toList(),
                            onChanged: (v) => v == null ? null : _changeStatus(u, v),
                          )),
                          DataCell(Row(children: [
                            IconButton(
                              tooltip: 'Reset password',
                              icon: const Icon(Icons.password, size: 18),
                              onPressed: () => _resetPassword(u),
                            ),
                            IconButton(
                              tooltip: 'Delete user',
                              icon: const Icon(Icons.delete_outline, color: AppColors.colError, size: 18),
                              onPressed: () => _deleteUser(u),
                            ),
                          ])),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('➕ Create User', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _newUserCtrl,
                        decoration: const InputDecoration(labelText: 'Username'),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _newEmailCtrl,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _newPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<UserTier>(
                        initialValue: _newTier,
                        decoration: const InputDecoration(labelText: 'Tier'),
                        items: UserTier.values
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                            .toList(),
                        onChanged: (v) => setState(() => _newTier = v!),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _createUser,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.colSuccess),
                      child: const Text('➕ Create User'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

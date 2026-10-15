import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';

/// Owner > Cashiers. Cashiers come and go, so the owner manages them here.
/// Nobody is ever deleted: leavers are deactivated so old sales keep their name.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashiers', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCashier(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add cashier'),
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final list = session.allStaff;
          return ListView.separated(
            // Bottom padding so the last row isn't hidden under the button.
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _StaffRow(staff: list[i]),
          );
        },
      ),
    );
  }

  Future<void> _addCashier(BuildContext context) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _AddCashierDialog());
    if (name == null || !context.mounted) return;
    SessionService.instance.addCashier(name); // not awaited: works offline
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name added. They set their own PIN the first time they sign in.')),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.staff});

  final Staff staff;

  String get _initials {
    final parts = staff.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _status {
    if (!staff.active) return 'Deactivated';
    final role = staff.isOwner ? 'Owner' : 'Cashier';
    final pin = staff.hasPin ? 'PIN set' : 'sets PIN at first sign-in';
    final products = (!staff.isOwner && staff.canManageProducts) ? ' · manages products' : '';
    return '$role · $pin$products';
  }

  @override
  Widget build(BuildContext context) {
    final dim = !staff.active;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: dim ? AppColors.surfaceMuted : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: dim ? AppColors.border : AppColors.primaryTint,
            foregroundColor: dim ? AppColors.inkSoft : AppColors.primary,
            child: Text(_initials, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: dim ? AppColors.inkSoft : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_status, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ],
            ),
          ),
          // The owner's own record has no menu: deactivating or resetting
          // the owner from the app could lock everyone out of this screen.
          if (!staff.isOwner) _StaffMenu(staff: staff),
        ],
      ),
    );
  }
}

class _StaffMenu extends StatelessWidget {
  const _StaffMenu({required this.staff});

  final Staff staff;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Options for ${staff.name}',
      onSelected: (action) => _handle(context, action),
      itemBuilder: (_) => [
        if (staff.active)
          PopupMenuItem(
            value: 'products',
            child: Text(staff.canManageProducts ? 'Remove product access' : 'Allow managing products'),
          ),
        if (staff.active && staff.hasPin) const PopupMenuItem(value: 'reset', child: Text('Reset PIN')),
        if (staff.active) const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
        if (!staff.active) const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
      ],
    );
  }

  Future<void> _handle(BuildContext context, String action) async {
    final session = SessionService.instance;
    final messenger = ScaffoldMessenger.of(context);

    if (action == 'products') {
      final allow = !staff.canManageProducts;
      session.setCanManageProducts(staff, allow);
      messenger.showSnackBar(SnackBar(
        content: Text(allow
            ? '${staff.name} can now add and edit products.'
            : '${staff.name} can no longer change products.'),
      ));
      return;
    }

    if (action == 'reactivate') {
      session.setActive(staff, true);
      messenger.showSnackBar(SnackBar(content: Text('${staff.name} can sign in again.')));
      return;
    }

    if (action == 'deactivate' && session.current?.id == staff.id) {
      // Deactivating the person on shift would yank the app out from
      // under this open screen. Make them switch first instead.
      messenger.showSnackBar(
        SnackBar(content: Text('${staff.name} is on shift right now. Switch shifts first, then deactivate.')),
      );
      return;
    }

    final isReset = action == 'reset';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isReset ? 'Reset ${staff.name}\'s PIN?' : 'Deactivate ${staff.name}?'),
        content: Text(
          isReset
              ? 'They will set a new PIN the next time they tap their name.'
              : 'They will disappear from the sign-in screen. Their past sales stay in the records.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(isReset ? 'Reset PIN' : 'Deactivate')),
        ],
      ),
    );
    if (ok != true) return;

    if (isReset) {
      session.resetPin(staff);
      messenger.showSnackBar(SnackBar(content: Text('${staff.name}\'s PIN was reset.')));
    } else {
      session.setActive(staff, false);
      messenger.showSnackBar(SnackBar(content: Text('${staff.name} was deactivated.')));
    }
  }
}

class _AddCashierDialog extends StatefulWidget {
  const _AddCashierDialog();

  @override
  State<_AddCashierDialog> createState() => _AddCashierDialogState();
}

class _AddCashierDialogState extends State<_AddCashierDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) {
      setState(() => _error = 'Enter their name');
      return;
    }
    // Two active "Jane"s would be indistinguishable on the PIN screen.
    final clash = SessionService.instance.staff.any((s) => s.name.toLowerCase() == name.toLowerCase());
    if (clash) {
      setState(() => _error = 'There is already an active "$name". Add a surname or initial.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add cashier'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: 'Name, e.g. Mike O.', errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';

import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import 'staff_screen.dart';
import 'stock_history_screen.dart';

/// The owner area's landing page. For now just a menu; the sales
/// dashboard (wireframe 9) fills the top of this screen in step 8.
class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;
    final ownerOnShift = session.current?.isOwner ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Owner', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text("Today's sales dashboard arrives in step 8.", style: TextStyle(color: AppColors.inkSoft)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.badge_outlined,
          title: 'Cashiers',
          subtitle: 'Add, deactivate, reset PINs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StaffScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.history,
          title: 'Stock history',
          subtitle: 'Deliveries and corrections, with who did them',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StockHistoryScreen()),
          ),
        ),
        // Only shown when a cashier is on shift and the owner unlocked this
        // tab with their PIN: lets the owner close it before handing back.
        if (!ownerOnShift)
          _MenuTile(
            icon: Icons.lock_outline,
            title: 'Lock owner area',
            subtitle: 'Also locks by itself when you leave this tab',
            onTap: session.lockOwner,
          ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
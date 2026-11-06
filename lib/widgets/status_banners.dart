import 'package:flutter/material.dart';

import '../services/plan_service.dart';
import '../services/session_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

/// "Mon 7 Dec": short enough for a banner, and the weekday helps people
/// who think in "this Monday" rather than dates.
String planDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

const _redBg = Color(0xFFFEE4E2);

/// One line at the top of Sell, only during grace, pause or suspension.
/// The "last 7 days" countdown is NOT shown here: that's for the owner on
/// the Owner tab, so customers at the counter don't see it early.
class PlanBanner extends StatelessWidget {
  const PlanBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;
    final plan = PlanService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([session, plan]),
      builder: (context, _) {
        final shop = session.shop;
        if (shop == null) return const SizedBox.shrink();
        final s = plan.stateFor(shop);
        final isOwner = session.current?.isOwner ?? false;

        switch (s.phase) {
          case PlanPhase.grace:
            final ago = s.daysSinceEnd == 1 ? 'yesterday' : '${s.daysSinceEnd} days ago';
            return _Strip(
              bg: AppColors.warningBg,
              fg: AppColors.warning,
              icon: Icons.schedule,
              text: 'Plan ended $ago. Sales pause on ${planDate(s.pauseOn!)}. '
                  '${isOwner ? 'Renew from the Owner tab.' : 'Ask the owner to renew.'}',
            );
          case PlanPhase.paused:
            return _Strip(
              bg: _redBg,
              fg: AppColors.danger,
              icon: Icons.block,
              text: 'Sales paused: the plan ended on ${planDate(s.paidUntil!)}. '
                  'The owner can renew from the Owner tab.',
            );
          case PlanPhase.suspended:
            return const _Strip(
              bg: _redBg,
              fg: AppColors.danger,
              icon: Icons.block,
              text: 'Account on hold. Contact DukaPoint to turn sales back on.',
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// Shown only when sales are saved on this phone but not yet online.
/// Says nothing is lost, so a cashier doesn't redo a sale "to be safe".
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final n = sync.waiting;
        if (n == 0) return const SizedBox.shrink();
        final sales = n == 1 ? '1 sale' : '$n sales';
        return _Strip(
          bg: AppColors.warningBg,
          fg: AppColors.warning,
          icon: sync.offline ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
          text: sync.offline
              ? 'Offline · $sales waiting to send. Saved on this phone; they go up when data is back.'
              : 'Sending $sales…',
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.bg, required this.fg, required this.icon, required this.text});

  final Color bg;
  final Color fg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }
}
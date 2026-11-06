import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/device_service.dart';
import '../services/plan_service.dart';
import '../services/printer_service.dart';
import '../services/session_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/printer_chip.dart';

/// The ☰ menu, on every tab. Quick things anyone on shift may need, so
/// they don't hunt through the Owner tab: the printer now, incoming M-Pesa
/// payments after Daraja, and a way to reach you.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onSwitchCashier});

  /// The shell's own Switch cashier (it warns before clearing the cart).
  final VoidCallback onSwitchCashier;

  String _planText(PlanState s) => switch (s.phase) {
        PlanPhase.active || PlanPhase.unset => 'plan active',
        PlanPhase.endingSoon => s.daysLeft == 0 ? 'plan ends today' : 'plan ends in ${s.daysLeft} days',
        PlanPhase.grace => 'plan ended',
        PlanPhase.paused => 'sales paused',
        PlanPhase.suspended => 'on hold',
      };

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;
    final printers = PrinterService.instance;
    final sync = SyncService.instance;

    return Drawer(
      child: ListenableBuilder(
        // Every line here is live: printer, sync and plan can all change
        // while the drawer is open.
        listenable: Listenable.merge([session, printers, sync, PlanService.instance]),
        builder: (context, _) {
          final shop = session.shop;
          final plan = shop == null ? null : PlanService.instance.stateFor(shop);
          final look = printerLook(printers.status);

          // Close the drawer first, then do the thing, so the result (a
          // sheet, a dialog) appears over the screen, not under the drawer.
          void closeThen(void Function() action) {
            Navigator.pop(context);
            action();
          }

          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Header ----
                Container(
                  color: AppColors.surfaceMuted,
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop?.name ?? 'DukaPoint', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (session.current != null) '${session.current!.name} on shift',
                          if (plan != null) _planText(plan),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // ---- Printer ----
                if (printers.supported)
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('Printer'),
                    subtitle: Text(
                      printers.printer == null ? 'None chosen' : '${printers.printer!.name} · ${look.label}',
                      style: TextStyle(color: printers.printer == null ? AppColors.inkSoft : look.fg),
                    ),
                    onTap: () {
                      // Capture before the drawer closes and takes its
                      // context with it.
                      final ctx = Navigator.of(context).context;
                      closeThen(() => showPrinterSheet(ctx));
                    },
                  ),

                // ---- M-Pesa payments (after Daraja) ----
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.phone_android_outlined),
                  title: Text('M-Pesa payments'),
                  subtitle: Text('Coming with automatic M-Pesa'),
                ),

                // ---- Sync ----
                ListTile(
                  leading: Icon(
                    sync.waiting == 0
                        ? Icons.cloud_done_outlined
                        : sync.offline
                            ? Icons.cloud_off_outlined
                            : Icons.cloud_upload_outlined,
                    color: sync.waiting == 0 ? AppColors.success : AppColors.warning,
                  ),
                  title: const Text('Sync'),
                  subtitle: Text(
                    sync.waiting == 0
                        ? 'All sales saved online'
                        : sync.offline
                            ? 'Offline · ${sync.waiting} waiting to send'
                            : 'Sending ${sync.waiting}…',
                  ),
                ),
                const Divider(),

                // ---- Shift + help ----
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('Switch cashier'),
                  onTap: () => closeThen(onSwitchCashier),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help · Contact DukaPoint'),
                  subtitle: const Text('Call or WhatsApp'),
                  onTap: () {
                    final ctx = Navigator.of(context).context;
                    closeThen(() => _showHelp(ctx));
                  },
                ),

                const Spacer(),
                // The phone's tag: when a shop calls about "the second phone",
                // this tells you which one (it's in its receipt numbers too).
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
                  child: Text(
                    'DukaPoint · this phone ${DeviceService.instance.tag}',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showHelp(BuildContext context) {
    final phone = PlanService.instance.supportPhone;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Contact DukaPoint', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                phone == null ? 'The support number isn\'t set up yet.' : phone,
                style: phone == null ? const TextStyle(color: AppColors.inkSoft) : AppTheme.mono(size: 18),
              ),
              const SizedBox(height: 16),
              if (phone != null) ...[
                FilledButton.icon(
                  onPressed: () => _open(sheet, Uri(scheme: 'tel', path: phone)),
                  icon: const Icon(Icons.call),
                  label: const Text('Call'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  // WhatsApp wants the number in international form, no
                  // plus or leading zero: 0712345678 -> 254712345678.
                  onPressed: () => _open(sheet, Uri.parse('https://wa.me/${_international(phone)}')),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: AppColors.ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _international(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) return '254${digits.substring(1)}';
    return digits;
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that on this phone")),
      );
    }
  }
}
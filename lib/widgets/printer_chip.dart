import 'package:flutter/material.dart';

import '../screens/owner/printer_screen.dart';
import '../services/printer_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

/// Words and colours for each printer state. Colour never stands alone:
/// every state has its own word.
({String label, Color fg, Color bg}) printerLook(PrinterStatus s) => switch (s) {
      PrinterStatus.ready => (label: 'Ready', fg: AppColors.success, bg: AppColors.successBg),
      PrinterStatus.off => (label: 'Off', fg: AppColors.warning, bg: AppColors.warningBg),
      PrinterStatus.checking => (label: 'Checking…', fg: AppColors.inkSoft, bg: AppColors.surfaceMuted),
      PrinterStatus.none => (label: 'No printer', fg: AppColors.inkSoft, bg: AppColors.surfaceMuted),
      PrinterStatus.unsupported => (label: 'Phone only', fg: AppColors.inkSoft, bg: AppColors.surfaceMuted),
    };

/// "🖨 Ready" in the Sell cart header. Tap for the quick-fix sheet.
class PrinterChip extends StatelessWidget {
  const PrinterChip({super.key});

  @override
  Widget build(BuildContext context) {
    final printers = PrinterService.instance;
    return ListenableBuilder(
      listenable: printers,
      builder: (context, _) {
        // The web version can't print over Bluetooth: no chip at all,
        // rather than one that can never be fixed.
        if (!printers.supported) return const SizedBox.shrink();
        final look = printerLook(printers.status);
        return Material(
          color: look.bg,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showPrinterSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print_outlined, size: 16, color: look.fg),
                  const SizedBox(width: 4),
                  Text(look.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: look.fg)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The quick-fix sheet: what's wrong, Reconnect, Test print, and a way to
/// the full Printer page. Also opened from the drawer's Printer row.
Future<void> showPrinterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _PrinterSheet(),
  );
}

class _PrinterSheet extends StatelessWidget {
  const _PrinterSheet();

  String _explain(PrinterStatus s) => switch (s) {
        PrinterStatus.ready => 'Connected. Receipts print straight away.',
        PrinterStatus.off => "Can't reach it. Is it switched on, charged and close by?",
        PrinterStatus.checking => 'Trying to reach the printer…',
        PrinterStatus.none => 'No printer chosen on this phone yet.',
        PrinterStatus.unsupported => 'Printing works from the Android app.',
      };

  @override
  Widget build(BuildContext context) {
    final printers = PrinterService.instance;
    return ListenableBuilder(
      listenable: printers,
      builder: (context, _) {
        final p = printers.printer;
        final s = printers.status;
        final look = printerLook(s);
        final working = s == PrinterStatus.checking || printers.busy;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p?.name ?? 'Printer', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.print_outlined, size: 18, color: look.fg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${look.label} · ${_explain(s)}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: look.fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (p != null)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: working ? null : printers.checkStatus,
                          child: Text(s == PrinterStatus.checking ? 'Connecting…' : 'Reconnect'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: working
                              ? null
                              : () async {
                                  final outcome = await printers.printTest(SessionService.instance.shop?.name ?? 'DukaPoint');
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(outcome == PrintOutcome.printed ? 'Test slip printed' : outcome.message)),
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: AppColors.ink,
                          ),
                          child: Text(printers.busy ? 'Printing…' : 'Test print'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    // Grab the navigator first: once the sheet closes, its
                    // own context is gone and can't open anything.
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute(builder: (_) => const PrinterScreen()));
                  },
                  child: Text(p == null ? 'Choose a printer ›' : 'Change printer ›'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
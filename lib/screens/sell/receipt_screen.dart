import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/sale.dart';
import '../../services/printer_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/receipt_text.dart';

/// Wireframe 5. Shown right after a sale is saved (prints by itself if
/// auto-print is on), and again when a past sale is opened from the Sales
/// tab (Reprint). The paper card shows exactly what the printer prints.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.sale, this.viewOnly = false});

  final Sale sale;

  /// True when opened from the Sales tab: a past sale being looked at
  /// (or reprinted), not one that was just paid for.
  final bool viewOnly;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

enum _PrintState { idle, printing, printed, failed }

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _printers = PrinterService.instance;

  // Marks the white paper card, so Share can photograph exactly that.
  final _paperKey = GlobalKey();
  bool _sharing = false;

  _PrintState _state = _PrintState.idle;
  PrintOutcome? _lastOutcome;

  /// After one successful print on this screen, any further print is a
  /// copy and says REPRINT on it.
  bool _printedOnce = false;

  Sale get sale => widget.sale;

  @override
  void initState() {
    super.initState();
    final shouldAutoPrint = !widget.viewOnly && _printers.autoPrint && _printers.supported;
    if (shouldAutoPrint) {
      // After the first frame: the cashier sees "Payment received" at once,
      // and the Bluetooth work happens while they're reading it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _print());
    }
  }

  Future<void> _print() async {
    if (_state == _PrintState.printing) return;
    setState(() => _state = _PrintState.printing);

    final reprint = widget.viewOnly || _printedOnce;
    final lines = buildReceiptLines(sale, SessionService.instance.shop!, reprint: reprint);
    final outcome = await _printers.printReceipt(lines);

    // The cashier may already have tapped New sale; the print still
    // finishes in the background, there's just no screen left to update.
    if (!mounted) return;
    setState(() {
      _lastOutcome = outcome;
      if (outcome == PrintOutcome.printed) {
        _printedOnce = true;
        _state = _PrintState.printed;
      } else {
        _state = _PrintState.failed;
      }
    });
  }

  /// Shares a picture of the paper card, not text: WhatsApp shows text in
  /// its own proportional font, which breaks the columns, while a picture
  /// looks exactly like the printed receipt and previews right in the chat.
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _paperKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 3x the screen size: sharp when the customer zooms in on the
      // M-Pesa code, still only ~100 KB.
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) throw StateError('No image data');

      final shopName = SessionService.instance.shop!.name;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png')],
        // Without this the file gets a random name; with it, the customer
        // can find "Receipt-DMD-K7-000124.png" in their downloads later.
        fileNameOverrides: ['Receipt-${sale.receiptNo}.png'],
        text: 'Receipt ${sale.receiptNo} from $shopName',
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't share the receipt from this phone")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String get _summary {
    switch (sale.method) {
      case 'cash':
        return 'Cash · ${ksh(sale.total)} · Change ${ksh(sale.change ?? 0)}';
      case 'till':
        return 'M-Pesa · ${ksh(sale.total)} · ${sale.mpesaCode ?? ''}';
      default:
        return ksh(sale.total);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = SessionService.instance.shop!;
    final lines = buildReceiptLines(sale, shop);
    final printing = _state == _PrintState.printing;

    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      body: SafeArea(
        child: Column(
          children: [
            // ---- Success header ----
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: widget.viewOnly ? AppColors.surfaceMuted : AppColors.success,
                    child: Icon(
                      widget.viewOnly ? Icons.receipt_long_outlined : Icons.check,
                      color: widget.viewOnly ? AppColors.ink : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.viewOnly ? sale.receiptNo : 'Payment received',
                    style: widget.viewOnly
                        ? AppTheme.mono(size: 20)
                        : const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(_summary, style: const TextStyle(fontSize: 15, color: AppColors.inkSoft)),
                ],
              ),
            ),
            _statusStrip(),
            const Divider(height: 1),

            // ---- The receipt, as it prints ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                child: Center(
                  child: RepaintBoundary(
                    key: _paperKey,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _ReceiptPaper(lines: lines),
                    ),
                  ),
                ),
              ),
            ),

            // ---- Actions ----
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (!_printers.supported || printing) ? null : _print,
                          icon: printing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : const Icon(Icons.print_outlined),
                          label: Text(widget.viewOnly || _printedOnce ? 'Reprint' : 'Print'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sharing ? null : _share,
                          icon: _sharing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    // Never waits for the printer: a failed or slow print
                    // must not hold up the next customer.
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.viewOnly ? 'Close' : 'New sale'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One line under the header saying what the printer is doing. Nothing
  /// pops up over the screen: Retry is offered here, and ignoring it is
  /// the same as Skip.
  Widget _statusStrip() {
    switch (_state) {
      case _PrintState.idle:
        return const SizedBox.shrink();
      case _PrintState.printing:
        return const _Strip(
          bg: AppColors.surface,
          fg: AppColors.inkSoft,
          icon: Icons.print_outlined,
          text: 'Printing…',
          busy: true,
        );
      case _PrintState.printed:
        return const _Strip(
          bg: AppColors.successBg,
          fg: AppColors.success,
          icon: Icons.check_circle_outline,
          text: 'Printed',
        );
      case _PrintState.failed:
        final outcome = _lastOutcome!;
        // Retry only helps when something about the printer might change
        // in a moment (switched on, moved closer, Bluetooth turned on).
        final canRetry = outcome == PrintOutcome.unreachable || outcome == PrintOutcome.bluetoothOff;
        return _Strip(
          bg: AppColors.warningBg,
          fg: AppColors.warning,
          icon: Icons.print_disabled_outlined,
          text: outcome.message,
          action: canRetry ? TextButton(onPressed: _print, child: const Text('Retry')) : null,
        );
    }
  }
}

/// The receipt drawn in monospace, big lines at twice the size, so 16 big
/// characters take the same width as 32 normal ones, just like on paper.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({required this.lines});

  final List<ReceiptLine> lines;

  @override
  Widget build(BuildContext context) {
    final normal = AppTheme.mono(size: 12.5, weight: FontWeight.w400).copyWith(height: 1.45);
    final big = AppTheme.mono(size: 25, weight: FontWeight.w700).copyWith(height: 1.25);
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: i < lines.length - 1 ? '${lines[i].text}\n' : lines[i].text,
              style: lines[i].big ? big : normal,
            ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.text,
    this.busy = false,
    this.action,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
  final String text;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
              : Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.35))),
          if (action != null) action!,
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../services/printer_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/printer_chip.dart';

/// Picks THIS phone's receipt printer, prints a test slip, and turns
/// auto-print on or off. Open to everyone (from the printer chip on Sell,
/// the drawer, and Owner > Printer): a cashier whose printer died mid-shift
/// shouldn't have to find the owner to swap it.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final _printers = PrinterService.instance;

  List<BluetoothInfo>? _paired; // null until "Show paired printers" is tapped
  PrintOutcome? _listProblem;
  bool _loading = false;

  Future<void> _loadPaired() async {
    setState(() => _loading = true);
    final (list, problem) = await _printers.pairedPrinters();
    if (!mounted) return;
    setState(() {
      _paired = list;
      _listProblem = problem;
      _loading = false;
    });
  }

  Future<void> _choose(BluetoothInfo d) async {
    await _printers.choose(d);
    if (!mounted) return;
    _toast('${d.name} saved as this phone\'s printer. Tap Test print to check it.');
  }

  Future<void> _test() async {
    final outcome = await _printers.printTest(SessionService.instance.shop!.name);
    if (!mounted) return;
    _toast(outcome == PrintOutcome.printed ? 'Test slip sent to the printer' : outcome.message);
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        child: !_printers.supported
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: _Note(text: 'Printing works from the Android app. A browser can\'t reach Bluetooth printers.'),
              )
            // Rebuilds when a printer is chosen, forgotten, or busy printing.
            : ListenableBuilder(
                listenable: _printers,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    const _Section(title: "This phone's printer", note: 'Saved on this phone only. Each till phone picks its own.'),
                    _currentCard(),
                    const SizedBox(height: 28),

                    const _Section(
                      title: 'Choose a printer',
                      note: 'Pair it first in phone Settings > Bluetooth (PIN is usually 0000). Only paired devices show here.',
                    ),
                    _pairedList(),
                    const SizedBox(height: 28),

                    const _Section(title: 'Receipts', note: 'Applies to this phone only'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _printers.autoPrint,
                      onChanged: _printers.setAutoPrint,
                      title: const Text('Print automatically after each sale', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Turn off if this phone has no printer. The receipt can still be printed or shared by hand.'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _currentCard() {
    final p = _printers.printer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(p == null ? Icons.print_disabled_outlined : Icons.print_outlined,
                  color: p == null ? AppColors.inkSoft : AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p?.name ?? 'No printer chosen', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    if (p != null) Text(p.mac, style: AppTheme.mono(size: 13, weight: FontWeight.w400, color: AppColors.inkSoft)),
                    if (p != null) ...[
                      const SizedBox(height: 4),
                      // Same words and colours as the chip on Sell.
                      Builder(builder: (_) {
                        final look = printerLook(_printers.status);
                        return Text(look.label, style: TextStyle(fontWeight: FontWeight.w700, color: look.fg));
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _printers.busy ? null : _test,
              icon: _printers.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.receipt_long_outlined),
              label: Text(_printers.busy ? 'Printing…' : 'Test print'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _printers.busy ? null : _printers.forget,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Forget this printer'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pairedList() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final list = _paired;
    if (list == null) {
      return OutlinedButton.icon(
        onPressed: _loadPaired,
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Show paired printers'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: AppColors.ink),
      );
    }

    final problem = _listProblem;
    if (problem != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Note(text: problem.message, warn: true),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _loadPaired, child: const Text('Try again')),
        ],
      );
    }

    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Note(text: 'Nothing paired yet. Switch the printer on, pair it in phone Settings > Bluetooth, then tap Refresh.', warn: true),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _loadPaired, child: const Text('Refresh')),
        ],
      );
    }

    final chosenMac = _printers.printer?.mac;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in list)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: d.macAdress == chosenMac ? AppColors.primary : AppColors.border,
                width: d.macAdress == chosenMac ? 2 : 1,
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(d.name.isEmpty ? 'Unnamed device' : d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d.macAdress, style: AppTheme.mono(size: 12, weight: FontWeight.w400, color: AppColors.inkSoft)),
              trailing: d.macAdress == chosenMac
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : const Text('Use', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              onTap: d.macAdress == chosenMac ? null : () => _choose(d),
            ),
          ),
        TextButton.icon(
          onPressed: _loadPaired,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh list'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(note, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? AppColors.warningBg : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 15, height: 1.4, color: warn ? AppColors.warning : AppColors.ink)),
    );
  }
}
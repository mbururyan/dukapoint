import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/receipt_text.dart';

/// Every way a print can end. The screens show [message] as-is, so the
/// cashier always gets a reason and a next step, never just "failed".
enum PrintOutcome {
  printed,
  noPrinterChosen,
  notSupported,
  noPermission,
  bluetoothOff,
  unreachable;

  String get message => switch (this) {
        PrintOutcome.printed => 'Printed',
        PrintOutcome.noPrinterChosen => 'No printer chosen yet. The owner can pick one in Owner > Printer.',
        PrintOutcome.notSupported => 'Printing works from the Android app, not the browser.',
        PrintOutcome.noPermission =>
          'DukaPoint needs "Nearby devices" to reach the printer. Allow it in phone Settings > Apps > DukaPoint > Permissions.',
        PrintOutcome.bluetoothOff => 'Bluetooth is off. Turn it on and try again.',
        PrintOutcome.unreachable => "Couldn't reach the printer. Check it's on, charged and close by.",
      };
}

class SavedPrinter {
  const SavedPrinter({required this.name, required this.mac});
  final String name;
  final String mac;
}

/// The Bluetooth receipt printer for THIS phone.
///
/// Saved on the phone, not in Firestore: each till phone pairs with the
/// printer sitting next to it, and two phones in one shop may use two
/// different printers.
class PrinterService extends ChangeNotifier {
  PrinterService._();
  static final instance = PrinterService._();

  static const _macKey = 'printerMac';
  static const _nameKey = 'printerName';
  static const _autoKey = 'autoPrint';

  late SharedPreferences _prefs;

  SavedPrinter? printer;
  bool autoPrint = true;

  /// True while a print job is talking to the printer, so buttons can
  /// show a spinner instead of being tapped again.
  bool busy = false;

  Generator? _generator;

  // Print jobs run one at a time. Two quick taps (or an auto-print plus a
  // manual reprint) would otherwise interleave their bytes on one
  // Bluetooth link and print garbage.
  Future<void> _queue = Future.value();

  /// Android only for now: the browser can't open a classic Bluetooth
  /// link, and the web POS will print through the browser later.
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Call once in main().
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final mac = _prefs.getString(_macKey);
    if (mac != null) {
      printer = SavedPrinter(name: _prefs.getString(_nameKey) ?? 'Printer', mac: mac);
    }
    autoPrint = _prefs.getBool(_autoKey) ?? true;
  }

  // -------------------------------------------------------------------
  // Choosing a printer
  // -------------------------------------------------------------------

  /// Printers already paired in the phone's Bluetooth settings. We don't
  /// scan for new devices ourselves: pairing in Android settings handles
  /// the PIN (0000) and needs no location permission.
  Future<(List<BluetoothInfo>, PrintOutcome?)> pairedPrinters() async {
    final problem = await _checkPhone();
    if (problem != null) return (const <BluetoothInfo>[], problem);
    // A copy, so sorting never touches a list the plugin might reuse.
    final list = List.of(await PrintBluetoothThermal.pairedBluetooths);
    // Earbuds and car kits are paired too. Likely printers go first so
    // the owner doesn't have to hunt for "MTP-II" among them.
    bool looksLikePrinter(BluetoothInfo d) =>
        RegExp(r'print|pos|mtp|pt-?\d|rpp|xp-', caseSensitive: false).hasMatch(d.name);
    list.sort((a, b) {
      final pa = looksLikePrinter(a) ? 0 : 1;
      final pb = looksLikePrinter(b) ? 0 : 1;
      return pa != pb ? pa - pb : a.name.compareTo(b.name);
    });
    return (list, null);
  }

  Future<void> choose(BluetoothInfo device) async {
    // Drop any link to the old printer so the next print opens a fresh
    // one to the new printer.
    if (supported) await PrintBluetoothThermal.disconnect;
    printer = SavedPrinter(name: device.name, mac: device.macAdress);
    await _prefs.setString(_macKey, device.macAdress);
    await _prefs.setString(_nameKey, device.name);
    notifyListeners();
  }

  Future<void> forget() async {
    if (supported) await PrintBluetoothThermal.disconnect;
    printer = null;
    await _prefs.remove(_macKey);
    await _prefs.remove(_nameKey);
    notifyListeners();
  }

  Future<void> setAutoPrint(bool on) async {
    autoPrint = on;
    await _prefs.setBool(_autoKey, on);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Printing
  // -------------------------------------------------------------------

  /// 58mm paper, 32 characters a line in the normal font. Built once:
  /// loading the capability profile reads a file from the package.
  Future<Generator> generator() async =>
      _generator ??= Generator(PaperSize.mm58, await CapabilityProfile.load());

  /// Sends ready-made ESC/POS bytes. Never throws: every problem comes
  /// back as a [PrintOutcome] the screen can show.
  Future<PrintOutcome> printBytes(List<int> bytes) {
    final job = _queue.then((_) => _send(bytes));
    // The next job waits for this one whether it worked or not.
    _queue = job.then((_) {}, onError: (_) {});
    return job;
  }

  Future<PrintOutcome> _send(List<int> bytes) async {
    final p = printer;
    if (!supported) return PrintOutcome.notSupported;
    if (p == null) return PrintOutcome.noPrinterChosen;
    final problem = await _checkPhone();
    if (problem != null) return problem;

    _setBusy(true);
    try {
      // Two tries. The link can say "connected" after the printer was
      // switched off or carried out of range; the first write then fails,
      // so we drop the stale link and connect again from scratch.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!await PrintBluetoothThermal.connectionStatus) {
          final ok = await PrintBluetoothThermal.connect(macPrinterAddress: p.mac)
              // A printer that's off can keep connect() waiting for a long
              // time; the customer is standing there, so give up sooner.
              .timeout(const Duration(seconds: 10), onTimeout: () => false);
          if (!ok) continue;
        }
        if (await PrintBluetoothThermal.writeBytes(bytes)) return PrintOutcome.printed;
        await PrintBluetoothThermal.disconnect;
      }
      return PrintOutcome.unreachable;
    } catch (_) {
      return PrintOutcome.unreachable;
    } finally {
      _setBusy(false);
    }
  }

  static const _bigStyle = PosStyles(
    bold: true,
    height: PosTextSize.size2,
    width: PosTextSize.size2,
  );

  /// Prints the lines from buildReceiptLines(). They arrive already
  /// padded and centred, so each one is sent as-is: what the cashier sees
  /// on screen is exactly what comes out.
  Future<PrintOutcome> printReceipt(List<ReceiptLine> lines) async {
    final g = await generator();
    final bytes = <int>[...g.reset()];
    for (final l in lines) {
      if (l.text.trim().isEmpty) {
        bytes.addAll(g.feed(1));
        continue;
      }
      bytes.addAll(g.text(_printable(l.text), styles: l.big ? _bigStyle : const PosStyles()));
    }
    // No cutter on this printer: feed enough paper to tear below the text.
    bytes.addAll(g.feed(3));
    return printBytes(bytes);
  }

  /// The printer only has plain Latin characters. A curly apostrophe in
  /// "Mama Njeri’s Duka" or an emoji in a product name would otherwise
  /// make the whole print fail, so they're swapped for plain ones.
  static String _printable(String s) {
    const swaps = {'‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '×': 'x'};
    final out = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final swap = swaps[ch];
      if (swap != null) {
        out.write(swap);
      } else if (r >= 32 && r < 127) {
        out.write(ch);
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }

  /// A short slip that proves three things: the link works, the big bold
  /// font works (used for the shop name and total), and 32 characters fit
  /// on one line (what the receipt layout assumes).
  Future<PrintOutcome> printTest(String shopName) async {
    final g = await generator();
    const big = PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    );
    const center = PosStyles(align: PosAlign.center);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');

    final bytes = <int>[
      ...g.reset(),
      ...g.text(_printable(shopName.toUpperCase()), styles: big),
      ...g.text('Printer test', styles: center),
      ...g.hr(),
      ...g.text('12345678901234567890123456789012'),
      ...g.text('If the numbers above fit on one line, receipts will line up.'),
      ...g.hr(),
      ...g.text('${two(now.day)}/${two(now.month)}/${now.year} ${two(now.hour)}:${two(now.minute)}', styles: center),
      ...g.text('Powered by DukaPoint', styles: center),
      // No cutter on this printer: feed enough paper to tear below the text.
      ...g.feed(3),
    ];
    return printBytes(bytes);
  }

  // -------------------------------------------------------------------

  /// Android 12+ asks the user for "Nearby devices" before any app can
  /// talk to a Bluetooth device. Older phones grant it automatically.
  ///
  /// The plugin's own call does the asking, on purpose: the plugin refuses
  /// every Bluetooth call unless BOTH "connect" and "scan" are granted, and
  /// quietly answers "off" / "no devices" when one is missing. Asking for
  /// just "connect" ourselves is what made Bluetooth look off on the
  /// Infinix while RawBT printed fine.
  Future<PrintOutcome?> _checkPhone() async {
    if (!supported) return PrintOutcome.notSupported;
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) return PrintOutcome.noPermission;
    if (!await PrintBluetoothThermal.bluetoothEnabled) return PrintOutcome.bluetoothOff;
    return null;
  }

  void _setBusy(bool v) {
    busy = v;
    notifyListeners();
  }
}
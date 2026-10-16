import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cart_service.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'receipt_screen.dart';

/// Wireframe 4. Pay first, then the receipt (decided Monday): the sale is
/// only saved once the cash covers the total or an M-Pesa code is typed.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _cart = CartService.instance;
  final _cash = TextEditingController();
  final _code = TextEditingController();

  String _method = 'cash'; // 'cash' | 'till' | 'stk'
  bool _saving = false;

  // M-Pesa confirmation codes are 10 capital letters/digits (e.g. SJK3A1B2C4).
  static final _codePattern = RegExp(r'^[A-Z0-9]{10}$');

  int get _total => _cart.total;
  int? get _tendered => int.tryParse(_cash.text.trim());

  @override
  void dispose() {
    _cash.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Quick buttons: the exact amount, then the notes a customer is likely
  /// to hand over (next 100, 500, 1,000 above the total).
  List<int> get _quickAmounts {
    int up(int step) => ((_total + step - 1) ~/ step) * step;
    final set = <int>{_total, up(100), up(500), up(1000)};
    return set.toList()..sort();
  }

  bool get _canConfirm {
    if (_saving || _cart.isEmpty) return false;
    switch (_method) {
      case 'cash':
        final t = _tendered;
        return t != null && t >= _total;
      case 'till':
        return _codePattern.hasMatch(_code.text.trim());
      default:
        return false; // M-Pesa prompt comes later
    }
  }

  String get _blockedLabel {
    switch (_method) {
      case 'cash':
        return _cash.text.trim().isEmpty ? 'Enter amount received' : 'Amount is less than the total';
      case 'till':
        return 'Enter the 10-character M-Pesa code';
      default:
        return 'Not available yet';
    }
  }

  void _confirm() {
    if (!_canConfirm) return;
    // Lock the button at once: a double tap must never make two sales.
    setState(() => _saving = true);

    final sale = SalesService.instance.record(
      // A copy of the lines: the cart is cleared right after.
      lines: List.of(_cart.lines),
      method: _method,
      tendered: _method == 'cash' ? _tendered : null,
      change: _method == 'cash' ? _tendered! - _total : null,
      mpesaCode: _method == 'till' ? _code.text.trim() : null,
    );
    _cart.clear();

    // Replace checkout with the receipt, so Back from the receipt returns
    // to an empty Sell screen, not to this already-paid checkout.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReceiptScreen(sale: sale)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = SessionService.instance.shop!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                children: [
                  // ---- Total ----
                  Center(
                    child: Text(
                      'Total due · ${_cart.itemCount} ${_cart.itemCount == 1 ? 'item' : 'items'}',
                      style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(child: Text(ksh(_total), style: AppTheme.mono(size: 38))),
                  const SizedBox(height: 24),

                  // ---- Method ----
                  const Text('Payment method', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MethodCard(label: 'Cash', sub: 'Shows change', selected: _method == 'cash', onTap: () => setState(() => _method = 'cash')),
                      const SizedBox(width: 8),
                      _MethodCard(label: 'M-Pesa Till', sub: 'Buy Goods', selected: _method == 'till', onTap: () => setState(() => _method = 'till')),
                      const SizedBox(width: 8),
                      _MethodCard(label: 'M-Pesa prompt', sub: 'Later', selected: _method == 'stk', onTap: () => setState(() => _method = 'stk')),
                    ],
                  ),
                  const SizedBox(height: 22),

                  if (_method == 'cash') _cashPanel(),
                  if (_method == 'till') _tillPanel(shop.tillNumber),
                  if (_method == 'stk') _stkPanel(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _canConfirm ? _confirm : null,
                child: Text(_canConfirm ? 'Confirm payment' : _blockedLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cashPanel() {
    final t = _tendered;
    final changeText = t == null
        ? '—'
        : t >= _total
            ? ksh(t - _total)
            : '${ksh(_total - t)} short';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cash,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          style: AppTheme.mono(size: 22),
          decoration: const InputDecoration(labelText: 'Amount received', prefixText: 'Ksh '),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _quickAmounts)
              OutlinedButton(
                onPressed: () => setState(() => _cash.text = '$a'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink),
                child: Text(a == _total ? 'Exact' : kes(a), style: AppTheme.mono(size: 15)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Change', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(
                changeText,
                style: AppTheme.mono(size: 24, color: (t != null && t < _total) ? AppColors.danger : AppColors.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tillPanel(String till) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Customer pays to Buy Goods Till', style: TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 4),
              Text(
                till.isEmpty ? 'Not set' : till,
                style: AppTheme.mono(size: 28, color: till.isEmpty ? AppColors.danger : AppColors.ink),
              ),
              const SizedBox(height: 6),
              const Text(
                'Check the M-Pesa SMS on the till phone, then type its code below.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          inputFormatters: [
            // Upper-case as they type, letters and digits only, so
            // "sjk3a1b2c4" and "SJK3A1B2C4 " are both saved the same way.
            TextInputFormatter.withFunction((old, now) {
              final t = now.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
              // Cursor to the end: removing a space would otherwise leave
              // it pointing past the text and crash.
              return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
            }),
          ],
          onChanged: (_) => setState(() {}),
          style: AppTheme.mono(size: 22),
          decoration: const InputDecoration(labelText: 'M-Pesa confirmation code', hintText: 'e.g. SJK3A1B2C4'),
        ),
      ],
    );
  }

  Widget _stkPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(12)),
      child: const Text(
        "Coming later. The customer gets a prompt on their phone and the receipt prints once Safaricom confirms. "
        "It needs internet and the shop's own Daraja approval. For now, use Till or Cash.",
        style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.warning),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.label, required this.sub, required this.selected, required this.onTap});

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.border, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.ink),
                ),
                Text(sub, style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : AppColors.inkSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
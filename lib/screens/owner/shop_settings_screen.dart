import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/device_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/new_pin_sheet.dart';

/// Wireframe 10 (minus Cashiers, which has its own screen, and the printer,
/// which arrives in step 6). Everything here prints on the receipt or
/// shows at checkout, so the owner can keep it right without calling you.
class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _session = SessionService.instance;

  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _footer;
  late final TextEditingController _till;
  late final TextEditingController _paybill;
  late final TextEditingController _account;
  late final TextEditingController _pochi;
  late String _mpesaType;

  @override
  void initState() {
    super.initState();
    final s = _session.shop!;
    _name = TextEditingController(text: s.name);
    _address = TextEditingController(text: s.address);
    _phone = TextEditingController(text: s.phone);
    _footer = TextEditingController(text: s.receiptFooter);
    _till = TextEditingController(text: s.tillNumber);
    _paybill = TextEditingController(text: s.paybillNumber);
    _account = TextEditingController(text: s.paybillAccount);
    _pochi = TextEditingController(text: s.pochiNumber);
    _mpesaType = s.mpesaType;
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _footer, _till, _paybill, _account, _pochi]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Enter the $what' : null;

  /// Safaricom numbers start 07 or 01 and have 10 digits.
  String? _phoneCheck(String? v, {required bool required}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? 'Enter the phone number' : null;
    if (!RegExp(r'^0[17]\d{8}$').hasMatch(t)) return 'Use 10 digits, starting 07 or 01';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    String t(TextEditingController c) => c.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    _session.updateShop({
      'name': t(_name),
      'address': t(_address),
      'phone': t(_phone),
      'receiptFooter': t(_footer),
      'mpesaType': _mpesaType,
      // All four are saved, not just the chosen type's: switching from
      // Paybill to Till and back shouldn't make the owner retype anything.
      'tillNumber': t(_till),
      'paybillNumber': t(_paybill),
      'paybillAccount': t(_account),
      'pochiNumber': t(_pochi),
    }); // not awaited: works offline

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop settings saved')));
  }

  Future<void> _changeOwnerPin() async {
    final owner = _session.ownerRecord;
    if (owner == null) return;
    final pin = await askNewPin(context, forName: owner.name);
    if (pin == null || !mounted) return;
    _session.setPin(owner, pin); // not awaited, same as at first sign-in
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${owner.name}'s PIN was changed. Use the new one from now on.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = _session.shop!;
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop settings', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ---- Receipt header ----
              const _Section(title: 'Receipt header', note: 'Prints at the top and bottom of every receipt'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Shop name'),
                validator: (v) => _required(v, 'shop name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Location', hintText: 'e.g. Membley, Ruiru'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: digits,
                style: AppTheme.mono(size: 16, weight: FontWeight.w500),
                decoration: const InputDecoration(labelText: 'Shop phone'),
                validator: (v) => _phoneCheck(v, required: false),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _footer,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 64, // two receipt lines at most
                decoration: const InputDecoration(labelText: 'Footer line', hintText: 'e.g. Asante, karibu tena'),
              ),
              const SizedBox(height: 16),

              // ---- M-Pesa ----
              const _Section(title: 'M-Pesa', note: 'What customers see at checkout and on the receipt'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'till', label: Text('Till')),
                  ButtonSegment(value: 'paybill', label: Text('Paybill')),
                  ButtonSegment(value: 'pochi', label: Text('Pochi')),
                ],
                selected: {_mpesaType},
                onSelectionChanged: (s) => setState(() => _mpesaType = s.first),
              ),
              const SizedBox(height: 12),
              if (_mpesaType == 'till')
                TextFormField(
                  controller: _till,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  style: AppTheme.mono(size: 18, weight: FontWeight.w500),
                  decoration: const InputDecoration(labelText: 'Buy Goods Till number'),
                  validator: (v) => _required(v, 'till number'),
                ),
              if (_mpesaType == 'paybill') ...[
                TextFormField(
                  controller: _paybill,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  style: AppTheme.mono(size: 18, weight: FontWeight.w500),
                  decoration: const InputDecoration(labelText: 'Paybill (business) number'),
                  validator: (v) => _required(v, 'paybill number'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _account,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Account number',
                    hintText: 'e.g. ${shop.code} or the shop name',
                    helperText: 'What customers type as "Account no."',
                  ),
                ),
              ],
              if (_mpesaType == 'pochi')
                TextFormField(
                  controller: _pochi,
                  keyboardType: TextInputType.phone,
                  inputFormatters: digits,
                  style: AppTheme.mono(size: 18, weight: FontWeight.w500),
                  decoration: const InputDecoration(labelText: 'Pochi la Biashara phone number'),
                  validator: (v) => _phoneCheck(v, required: true),
                ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Save settings')),
              const SizedBox(height: 28),

              // ---- Security ----
              const _Section(title: 'Security', note: 'Cashiers are managed under Owner > Cashiers'),
              OutlinedButton.icon(
                onPressed: _changeOwnerPin,
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Change owner PIN'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.ink,
                ),
              ),
              const SizedBox(height: 28),

              // ---- Read-only info ----
              const _Section(title: 'About this shop', note: 'Set by DukaPoint'),
              _InfoRow(label: 'Receipt code', value: shop.code),
              _InfoRow(label: 'This phone', value: DeviceService.instance.tag),
              _InfoRow(label: 'Plan', value: shop.isActive ? 'Active' : 'Suspended'),
            ],
          ),
        ),
      ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkSoft)),
          Text(value, style: AppTheme.mono(size: 15)),
        ],
      ),
    );
  }
}
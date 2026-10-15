import 'package:flutter/material.dart';

import '../screens/owner/owner_gate.dart';
import '../screens/products/products_screen.dart';
import '../screens/sell/sell_screen.dart';
import '../services/cart_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _sellTab = 0;
  static const _ownerTab = 3;

  int _index = _sellTab;

  void _selectTab(int i) {
    // Leaving the Owner tab re-locks it, so an owner who unlocked it
    // during a cashier's shift can't forget and leave it open.
    if (_index == _ownerTab && i != _ownerTab) SessionService.instance.lockOwner();
    // Close the keyboard from another tab's search box, so the scanner
    // gun's keystrokes go to the Sell screen instead.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = i);
  }

  /// Switching cashier clears the cart (a sale belongs to whoever rings it
  /// up), so warn first if there's something in it.
  Future<void> _switchCashier() async {
    final cart = CartService.instance;
    if (!cart.isEmpty) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Switch cashier?'),
          content: Text('The cart (${cart.itemCount} items, ${ksh(cart.total)}) will be cleared.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep selling')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Switch')),
          ],
        ),
      );
      if (yes != true) return;
    }
    cart.clear();
    SessionService.instance.endShift();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          session.shop?.name ?? '',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ShiftChip(name: session.current?.name ?? '', onTap: _switchCashier),
          ),
        ],
      ),
      // IndexedStack, not swapping widgets: a cashier who peeks at Sales
      // mid-sale must come back to the same screen state.
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            SellScreen(active: _index == _sellTab),
            const _Placeholder(title: 'Sales', note: 'Sales history arrives in step 7'),
            const ProductsScreen(),
            const OwnerGate(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_outline),
            selectedIcon: Icon(Icons.lock),
            label: 'Owner',
          ),
        ],
      ),
    );
  }
}

/// "Jane W. · Switch" pill in the top bar.
class _ShiftChip extends StatelessWidget {
  const _ShiftChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('$name · Switch', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}
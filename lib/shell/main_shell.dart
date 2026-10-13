import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../screens/owner/owner_gate.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _ownerTab = 3;

  int _index = 0;

  void _selectTab(int i) {
    // Leaving the Owner tab re-locks it, so an owner who unlocked it
    // during a cashier's shift can't forget and leave it open.
    if (_index == _ownerTab && i != _ownerTab) SessionService.instance.lockOwner();
    setState(() => _index = i);
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
            child: _ShiftChip(
              name: session.current?.name ?? '',
              // Ending the shift swaps this whole shell for the PIN screen,
              // so anything held in these widgets is thrown away. That's why
              // step 4 keeps the cart in a service, not in a screen.
              onTap: session.endShift,
            ),
          ),
        ],
      ),
      // IndexedStack, not swapping widgets: a cashier who peeks at Sales
      // mid-sale must come back to the same cart, not an empty one.
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            _Placeholder(
              title: 'Sell',
              note: 'Scanner + cart arrive in step 4',
              footer: 'Firebase project: ${Firebase.app().options.projectId}',
            ),
            const _Placeholder(title: 'Sales', note: 'Sales history arrives in step 7'),
            const _Placeholder(title: 'Products', note: 'Product list + scanning arrive in step 3'),
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
  const _Placeholder({required this.title, required this.note, this.footer});

  final String title;
  final String note;
  final String? footer;

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
          if (footer != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(footer!, style: AppTheme.mono(size: 13, color: AppColors.success)),
            ),
          ],
        ],
      ),
    );
  }
}
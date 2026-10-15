import 'package:cloud_firestore/cloud_firestore.dart';

/// A person who sells at the till. Lives at shops/{shopId}/staff/{staffId}.
/// Staff are not Firebase accounts: the phone is signed in as the shop,
/// and staff switch with a PIN.
class Staff {
  const Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.pinHash,
    required this.active,
    required this.canManageProducts,
  });

  final String id;
  final String name;
  final String role; // 'owner' | 'cashier'
  final String? pinHash; // null until the person sets a PIN on first use
  final bool active;
  // Set by the owner per trusted cashier. Owners always can.
  final bool canManageProducts;

  bool get isOwner => role == 'owner';
  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  factory Staff.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Staff(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Unnamed',
      role: (d['role'] as String?) ?? 'cashier',
      pinHash: d['pinHash'] as String?,
      // Missing 'active' counts as active, so a console doc without the
      // field still shows up instead of silently disappearing.
      active: (d['active'] as bool?) ?? true,
      // Missing = false: a new hire can't touch prices until the owner says so.
      canManageProducts: (d['canManageProducts'] as bool?) ?? false,
    );
  }
}
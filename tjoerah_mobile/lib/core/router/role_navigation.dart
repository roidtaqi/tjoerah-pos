import 'package:flutter/material.dart';

enum AppRole { owner, admin, areaManager, outletManager, cashier, production }

class RoleDestination {
  const RoleDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

AppRole appRoleForUser(Map<String, dynamic>? user) {
  final directRole = user?['role'];
  final direct = _appRoleFromValue(directRole?.toString());
  if (direct != null) return direct;

  final candidates = <String>[];
  final assignedRoles = user?['roles'];
  if (assignedRoles is List) {
    for (final role in assignedRoles) {
      if (role is Map) {
        final value = role['slug'] ?? role['name'];
        if (value != null) candidates.add(value.toString());
      } else if (role != null) {
        candidates.add(role.toString());
      }
    }
  }

  for (final candidate in candidates) {
    final role = _appRoleFromValue(candidate);
    if (role != null) return role;
  }
  return AppRole.outletManager;
}

AppRole? _appRoleFromValue(String? value) {
  final normalized = (value ?? '').toLowerCase().replaceAll(
    RegExp(r'[-_]'),
    ' ',
  );
  if (normalized.contains('owner')) return AppRole.owner;
  if (normalized.contains('admin')) return AppRole.admin;
  if (normalized.contains('area manager')) return AppRole.areaManager;
  if (normalized.contains('cashier') || normalized.contains('kasir')) {
    return AppRole.cashier;
  }
  if (normalized.contains('barista') ||
      normalized.contains('kitchen') ||
      normalized.contains('production') ||
      normalized.contains('dapur')) {
    return AppRole.production;
  }
  if (normalized.contains('outlet manager')) return AppRole.outletManager;
  return null;
}

Set<String> roleSlugsForUser(Map<String, dynamic>? user) {
  final roles = <String>{};
  final direct = user?['role']?.toString();
  if (direct != null) roles.add(_normalizedRoleSlug(direct));
  final assigned = user?['roles'];
  if (assigned is List) {
    for (final raw in assigned) {
      final value = raw is Map ? raw['slug'] ?? raw['name'] : raw;
      if (value != null) roles.add(_normalizedRoleSlug(value.toString()));
    }
  }
  return roles;
}

String _normalizedRoleSlug(String role) =>
    role.trim().toLowerCase().replaceAll(RegExp(r'[- ]'), '_');

String roleLabel(AppRole role) => switch (role) {
  AppRole.owner => 'Owner',
  AppRole.admin => 'Admin',
  AppRole.areaManager => 'Area Manager',
  AppRole.outletManager => 'Outlet Manager',
  AppRole.cashier => 'Kasir',
  AppRole.production => 'Tim Produksi',
};

String homePathForUser(Map<String, dynamic>? user) {
  return switch (appRoleForUser(user)) {
    AppRole.owner || AppRole.admin || AppRole.areaManager => '/dashboard',
    AppRole.outletManager || AppRole.cashier => '/pos',
    AppRole.production => '/kds',
  };
}

List<RoleDestination> destinationsForRole(AppRole role) => switch (role) {
  AppRole.owner || AppRole.admin => const [
    RoleDestination(
      path: '/dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    RoleDestination(
      path: '/operations',
      label: 'Operasional',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
    ),
    RoleDestination(
      path: '/inventory',
      label: 'Stok',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    RoleDestination(
      path: '/reports',
      label: 'Analitik',
      icon: Icons.query_stats_outlined,
      selectedIcon: Icons.query_stats_rounded,
    ),
    RoleDestination(
      path: '/settings',
      label: 'Lainnya',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
    ),
  ],
  AppRole.areaManager => const [
    RoleDestination(
      path: '/dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    RoleDestination(
      path: '/outlets',
      label: 'Outlet',
      icon: Icons.store_outlined,
      selectedIcon: Icons.store_rounded,
    ),
    RoleDestination(
      path: '/inventory',
      label: 'Stok',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    RoleDestination(
      path: '/reports',
      label: 'Laporan',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
    ),
    RoleDestination(
      path: '/settings',
      label: 'Lainnya',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
    ),
  ],
  AppRole.outletManager => const [
    RoleDestination(
      path: '/pos',
      label: 'POS',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
    ),
    RoleDestination(
      path: '/operations',
      label: 'Operasional',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
    ),
    RoleDestination(
      path: '/inventory',
      label: 'Stok',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    RoleDestination(
      path: '/reports',
      label: 'Laporan',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
    ),
    RoleDestination(
      path: '/settings',
      label: 'Lainnya',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
    ),
  ],
  AppRole.cashier => const [
    RoleDestination(
      path: '/pos',
      label: 'POS',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
    ),
    RoleDestination(
      path: '/orders',
      label: 'Pesanan',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
    ),
    RoleDestination(
      path: '/customers',
      label: 'Pelanggan',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
    ),
    RoleDestination(
      path: '/settings',
      label: 'Lainnya',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
    ),
  ],
  AppRole.production => const [
    RoleDestination(
      path: '/kds',
      label: 'Dapur',
      icon: Icons.soup_kitchen_outlined,
      selectedIcon: Icons.soup_kitchen_rounded,
    ),
    RoleDestination(
      path: '/settings',
      label: 'Lainnya',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
    ),
  ],
};

List<RoleDestination> destinationsForUser(Map<String, dynamic>? user) {
  final primary = destinationsForRole(appRoleForUser(user));
  final roles = roleSlugsForUser(user);
  final hasProductionRole = roles.any(
    (role) => const {'barista', 'kitchen_staff', 'production'}.contains(role),
  );
  if (!hasProductionRole || primary.any((item) => item.path == '/kds')) {
    return primary;
  }

  final result = [...primary];
  final settingsIndex = result.indexWhere((item) => item.path == '/settings');
  const production = RoleDestination(
    path: '/kds',
    label: 'Produksi',
    icon: Icons.soup_kitchen_outlined,
    selectedIcon: Icons.soup_kitchen_rounded,
  );
  settingsIndex < 0
      ? result.add(production)
      : result.insert(settingsIndex, production);
  return result;
}

bool canManageCatalogForUser(Map<String, dynamic>? user) {
  final roles = roleSlugsForUser(user);
  return roles.contains('owner') || roles.contains('admin');
}

bool canManageProductsForUser(Map<String, dynamic>? user) =>
    canManageCatalogForUser(user);

bool canCancelOrdersForUser(Map<String, dynamic>? user) =>
    canManageCatalogForUser(user);

bool canManageAttendanceForUser(Map<String, dynamic>? user) =>
    canManageCatalogForUser(user);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../theme/app_layout.dart';
import 'role_navigation.dart';

class ShellLayout extends ConsumerWidget {
  const ShellLayout({
    super.key,
    required this.child,
    required this.currentLocation,
  });

  final Widget child;
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = appRoleForUser(ref.watch(authProvider).user);
    final destinations = destinationsForRole(role);
    final currentIndex = _selectedIndex(destinations);
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width >= AppBreakpoints.tablet;
    final extended = width >= AppBreakpoints.desktop;

    if (showRail) {
      return Scaffold(
        body: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              child: NavigationRail(
                extended: extended,
                selectedIndex: currentIndex,
                onDestinationSelected: (index) =>
                    context.go(destinations[index].path),
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                groupAlignment: -0.82,
                leading: _RailBrand(extended: extended),
                destinations: destinations
                    .map(
                      (destination) => NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) =>
              context.go(destinations[index].path),
          destinations: destinations
              .map(
                (destination) => NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  int _selectedIndex(List<RoleDestination> destinations) {
    final index = destinations.indexWhere(
      (destination) => currentLocation == destination.path,
    );
    if (index >= 0) return index;

    if (currentLocation == '/kds' || currentLocation == '/outlets') {
      final operations = destinations.indexWhere(
        (destination) => destination.path == '/operations',
      );
      if (operations >= 0) return operations;
    }
    return 0;
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extended ? 192 : 56,
      height: 72,
      child: Row(
        mainAxisAlignment: extended
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'T',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (extended) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tjoerah POS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

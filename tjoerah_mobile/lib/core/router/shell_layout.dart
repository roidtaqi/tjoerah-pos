import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class ShellLayout extends StatefulWidget {
  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;

  const ShellLayout({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onNavigationChanged,
  });

  @override
  State<ShellLayout> createState() => _ShellLayoutState();
}

class _ShellLayoutState extends State<ShellLayout> {
  @override
  Widget build(BuildContext context) {
    // Determine if tablet for side navigation or phone for bottom navigation
    final isTablet = MediaQuery.of(context).size.width >= 600;

    if (isTablet) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: widget.currentIndex,
              onDestinationSelected: widget.onNavigationChanged,
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.surface,
              selectedIconTheme: const IconThemeData(color: AppColors.accent),
              selectedLabelTextStyle: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.point_of_sale), label: Text('POS')),
                NavigationRailDestination(icon: Icon(Icons.inventory_2), label: Text('Inventory')),
                NavigationRailDestination(icon: Icon(Icons.soup_kitchen), label: Text('KDS')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Reports')),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1, color: AppColors.border),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.currentIndex,
        onDestinationSelected: widget.onNavigationChanged,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.soup_kitchen), label: 'KDS'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/customers/screens/customers_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/kds/screens/kds_screen.dart';
import '../../features/operations/screens/operations_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/outlets/screens/outlets_screen.dart';
import '../../features/pos/screens/order_type_screen.dart';
import '../../features/pos/screens/payment_screen.dart';
import '../../features/pos/screens/pos_screen.dart';
import '../../features/pos/screens/table_selection_screen.dart';
import '../../features/pos/screens/table_management_screen.dart';
import '../../features/products/screens/product_management_screen.dart';
import '../../features/recipe/screens/recipe_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/reports/screens/shift_report_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import 'shell_layout.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) =>
          ShellLayout(currentLocation: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/operations',
          builder: (context, state) => const OperationsScreen(),
        ),
        GoRoute(
          path: '/outlets',
          builder: (context, state) => const OutletsScreen(),
        ),
        GoRoute(
          path: '/orders',
          builder: (context, state) => const OrdersScreen(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomersScreen(),
        ),
        GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
        GoRoute(path: '/kds', builder: (context, state) => const KdsScreen()),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => const InventoryScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/products/manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ProductManagementScreen(),
    ),
    GoRoute(
      path: '/tables',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TableSelectionScreen(),
    ),
    GoRoute(
      path: '/table-management',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TableManagementScreen(),
    ),
    GoRoute(
      path: '/recipes',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const RecipeScreen(),
    ),
    GoRoute(
      path: '/shift-report',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ShiftReportScreen(),
    ),
    GoRoute(
      path: '/order-type',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrderTypeScreen(),
    ),
    GoRoute(
      path: '/payment',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PaymentScreen(),
    ),
  ],
);

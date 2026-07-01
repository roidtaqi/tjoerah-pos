import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'package:provider/provider.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final auth = context.read<AuthProvider>();
    final isGoingToLogin = state.uri.path == '/login';

    if (!auth.isAuthenticated && !isGoingToLogin) {
      return '/login';
    }
    
    if (auth.isAuthenticated && isGoingToLogin) {
      return '/dashboard';
    }
    
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => DashboardScreen(),
    ),
  ],
);

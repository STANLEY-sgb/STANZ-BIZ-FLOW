import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../features/auth/auth_screens.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expenses/expenses_screens.dart';
import '../features/more/more_screens.dart';
import '../features/onboarding/accept_invitation_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/pos/pos_screen.dart';
import '../features/products/product_detail_screen.dart';
import '../features/products/product_form_screen.dart';
import '../features/products/products_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/sales/sales_screens.dart';
import 'shell.dart';

const _publicRoutes = {'/welcome', '/login', '/register', '/forgot-password'};
const _setupRoutes = {'/onboarding', '/setup', '/select-business', '/invite'};

/// Pure redirect policy so it can be unit-tested without a widget tree.
String? redirectFor(SessionState s, String location) {
  final path = Uri.parse(location).path;
  switch (s.status) {
    case SessionStatus.unknown:
      return path == '/splash' ? null : '/splash';
    case SessionStatus.signedOut:
      return _publicRoutes.contains(path) ? null : '/welcome';
    case SessionStatus.signedIn:
      if (_publicRoutes.contains(path) || path == '/splash') return '/home';
      // Offline at launch: no profile loaded, but a business was remembered. Let the user in.
      if (s.user == null) return s.activeBusinessId == null && !_setupRoutes.contains(path) ? '/onboarding' : null;
      if (s.businesses.isEmpty) return path == '/onboarding' || path == '/invite' ? null : '/onboarding';
      if (s.activeBusinessId == null) return _setupRoutes.contains(path) ? null : '/select-business';
      final m = s.activeMembership;
      final setupPending = m != null && !m.onboardingCompleted && (m.role == 'owner' || m.role == 'admin');
      if (setupPending &&
          !_setupRoutes.contains(path) &&
          !path.startsWith('/products') &&
          path != '/team' &&
          path != '/settings') {
        return '/setup';
      }
      return null;
  }
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(path: path, parentNavigatorKey: _rootKey, builder: (_, s) => build(s));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (_, state) => redirectFor(ref.read(sessionProvider), state.uri.toString()),
    routes: [
      page('/splash', (_) => const SplashScreen()),
      page('/welcome', (_) => const WelcomeScreen()),
      page('/login', (_) => const LoginScreen()),
      page('/register', (_) => const RegisterScreen()),
      page('/forgot-password', (_) => const ForgotPasswordScreen()),
      page('/onboarding', (_) => const CreateBusinessScreen()),
      page('/setup', (_) => const SetupChecklistScreen()),
      page('/select-business', (_) => const SelectBusinessScreen()),
      page('/invite', (s) => AcceptInvitationScreen(initialToken: s.uri.queryParameters['token'])),
      page('/products/new', (_) => const ProductFormScreen()),
      page('/products/:id', (s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
      page('/products/:id/edit', (s) => ProductFormScreen(productId: s.pathParameters['id'])),
      page('/sell/cart', (_) => const CheckoutScreen()),
      page('/sales', (_) => const SalesHistoryScreen()),
      page(
        '/sales/:id',
        (s) => ReceiptScreen(saleId: s.pathParameters['id']!, justCompleted: s.uri.queryParameters['new'] == '1'),
      ),
      page('/expenses', (_) => const ExpensesScreen()),
      page('/expenses/new', (_) => const ExpenseFormScreen()),
      page('/reports', (_) => const ReportsScreen()),
      page('/team', (_) => const TeamScreen()),
      page('/subscription', (_) => const SubscriptionScreen()),
      page('/settings', (_) => const BusinessSettingsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/sell', builder: (_, _) => const PosScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/products', builder: (_, _) => const ProductsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/inventory', builder: (_, _) => const ProductsScreen(inventoryMode: true))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())],
          ),
        ],
      ),
    ],
  );
});

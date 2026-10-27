import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../data/local/offline_providers.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/products/product_providers.dart';
import '../features/sales/sales_screens.dart';

/// Main navigation: bottom bar on phones, navigation rail on tablets.
/// Also owns the background sync engine for the signed-in business.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Sell'),
    (Icons.sell_outlined, Icons.sell_rounded, 'Products'),
    (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Inventory'),
    (Icons.menu_rounded, Icons.menu_open_rounded, 'More'),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncControllerProvider.notifier).start();
    });
  }

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    // When queued offline sales reach the server, refresh figures that depend on them.
    ref.listen(syncControllerProvider.select((s) => s.lastReport), (_, report) {
      if (report != null && report.changedServerData) {
        invalidateCatalog(ref);
        ref.invalidate(dashboardProvider);
        ref.invalidate(salesProvider);
      }
    });
    final destinations = AppShell.destinations;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: BizColors.surface,
              indicatorColor: BizColors.primaryContainer,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: BizColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
      ),
    );
  }
}

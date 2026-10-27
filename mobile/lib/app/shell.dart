import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';

/// Main navigation: bottom bar on phones, navigation rail on tablets.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Sell'),
    (Icons.sell_outlined, Icons.sell_rounded, 'Products'),
    (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Inventory'),
    (Icons.menu_rounded, Icons.menu_open_rounded, 'More'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
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

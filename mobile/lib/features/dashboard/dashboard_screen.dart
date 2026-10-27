import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

final dashboardPeriodProvider = NotifierProvider<_Period, String>(_Period.new);

class _Period extends Notifier<String> {
  @override
  String build() => 'today';
  void set(String v) => state = v;
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).dashboard(bid, ref.watch(dashboardPeriodProvider));
});

const _periods = {'today': 'Today', '7d': '7d', '30d': '30d', 'month': 'Month'};
const _comparisons = {
  'today': (vs: 'yesterday', none: 'No sales yesterday to compare'),
  '7d': (vs: 'the previous 7 days', none: 'No sales in the previous 7 days to compare'),
  '30d': (vs: 'the previous 30 days', none: 'No sales in the previous 30 days to compare'),
  'month': (vs: 'the same days last month', none: 'No sales in the same days last month to compare'),
};

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final business = ref.watch(currentBusinessProvider);
    final data = ref.watch(dashboardProvider);
    final period = ref.watch(dashboardPeriodProvider);
    final t = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: BizColors.navy,
              foregroundColor: Colors.white,
              title: const BrandLogo(size: 26, onDark: true),
              actions: [
                if (session.businesses.length > 1)
                  IconButton(
                    tooltip: 'Switch business',
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: () => context.push('/select-business'),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: ColoredBox(
                color: BizColors.navy,
                child: PageBody(
                  padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '$greeting${session.user == null ? '' : ', ${session.user!.firstName}'}',
                        style: t.bodyMedium?.copyWith(color: const Color(0xFFC9CEE0)),
                      ),
                      Text(
                        business.value?.name ?? '',
                        style: t.titleLarge?.copyWith(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: PageBody(
                padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.xl),
                child: AsyncView(
                  value: data,
                  onRetry: () => ref.invalidate(dashboardProvider),
                  loading: const _DashboardSkeleton(),
                  data: (d) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _QuickActions(business: business.value),
                      const SizedBox(height: Space.md),
                      if (d.fullScope) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              for (final e in _periods.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                            ],
                            selected: {period},
                            onSelectionChanged: (s) => ref.read(dashboardPeriodProvider.notifier).set(s.first),
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        _HeroMetric(d: d, comparison: _comparisons[period]!),
                        const SizedBox(height: Space.sm),
                        _MetricGrid(d: d),
                      ] else
                        _HeroCard(
                          label: 'My sales today',
                          value: d.mySalesAmount.format(d.currency),
                          footer: '${d.mySalesCount} ${d.mySalesCount == 1 ? 'sale' : 'sales'} recorded by you',
                        ),
                      if (d.lowStockCount > 0 || d.outOfStockCount > 0) ...[
                        SectionHeader('Needs restocking', action: 'View all', onAction: () => context.go('/inventory')),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (final (i, p) in d.lowStock.indexed) ...[
                                if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
                                ListTile(
                                  onTap: () => context.push('/products/${p.id}'),
                                  leading: Icon(
                                    Icons.warning_amber_rounded,
                                    color: p.onHand.isPositive ? BizColors.warning : BizColors.error,
                                  ),
                                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: StatusChip(
                                    p.onHand.isPositive ? '${p.onHand} left' : 'Out of stock',
                                    tone: p.onHand.isPositive ? Tone.warning : Tone.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (d.topProducts.isNotEmpty) ...[const SectionHeader('Top sellers'), _TopProducts(d: d)],
                      SectionHeader(
                        'Recent sales',
                        action: d.recentSales.isEmpty ? null : 'See all',
                        onAction: () => context.push('/sales'),
                      ),
                      if (d.recentSales.isEmpty)
                        AppCard(
                          child: Text(
                            d.activeProducts == 0
                                ? 'Add your first product, then record a sale to see it here.'
                                : 'No sales yet. Tap "New sale" to record your first one.',
                            style: t.bodyMedium?.copyWith(color: BizColors.textSecondary),
                          ),
                        )
                      else
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (final (i, s) in d.recentSales.indexed) ...[
                                if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
                                ListTile(
                                  onTap: () => context.push('/sales/${s.id}'),
                                  title: Text(s.receiptNumber),
                                  subtitle: Text(DateFormat.MMMd().add_jm().format(s.createdAt)),
                                  trailing: MoneyText(s.total.format(d.currency), style: t.titleSmall),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.business});

  final Business? business;

  @override
  Widget build(BuildContext context) {
    final b = business;
    final actions = [
      if (b?.can(Perm.salesCreate) ?? false) (Icons.point_of_sale_rounded, 'New sale', () => context.go('/sell'), true),
      if (b?.can(Perm.productsManage) ?? false)
        (Icons.add_box_outlined, 'Add product', () => context.push('/products/new'), false),
      if (b?.can(Perm.expensesManage) ?? false)
        (Icons.receipt_outlined, 'Expense', () => context.push('/expenses/new'), false),
    ];
    return Row(
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: Space.xs),
          Expanded(
            child: Material(
              color: a.$4 ? BizColors.primary : BizColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: Radii.control,
                side: BorderSide(color: a.$4 ? BizColors.primary : BizColors.border),
              ),
              child: InkWell(
                borderRadius: Radii.control,
                onTap: a.$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Column(
                    children: [
                      Icon(a.$1, color: a.$4 ? Colors.white : BizColors.secondary),
                      const SizedBox(height: Space.xxs),
                      Text(
                        a.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: a.$4 ? Colors.white : BizColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.label, required this.value, required this.footer, this.trend});

  final String label;
  final String value;
  final String footer;
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        // A single restrained gradient on the hero metric only.
        gradient: const LinearGradient(
          colors: [BizColors.navy, BizColors.navySoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodyMedium?.copyWith(color: const Color(0xFFC9CEE0))),
          const SizedBox(height: Space.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.displaySmall!.copyWith(color: Colors.white).tabular),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              if (trend != null) ...[trend!, const SizedBox(width: Space.xs)],
              Expanded(
                child: Text(footer, style: t.bodySmall?.copyWith(color: const Color(0xFFC9CEE0))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.d, required this.comparison});

  final DashboardData d;
  final ({String vs, String none}) comparison;

  @override
  Widget build(BuildContext context) {
    final cur = d.current!;
    final prev = d.previous!;
    Widget? trend;
    if (!prev.netSales.isZero) {
      // Percentage change computed with integer arithmetic on minor units.
      final pct = ((cur.netSales.minor - prev.netSales.minor) * BigInt.from(100)) ~/ prev.netSales.minor.abs();
      final up = pct >= BigInt.zero;
      trend = StatusChip(
        '${up ? '+' : ''}$pct%',
        tone: up ? Tone.success : Tone.error,
        icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      );
    }
    return _HeroCard(
      label: 'Net sales',
      value: cur.netSales.format(d.currency),
      trend: trend,
      footer: prev.netSales.isZero
          ? '${cur.salesCount} ${cur.salesCount == 1 ? 'sale' : 'sales'} · ${comparison.none}'
          : '${cur.salesCount} ${cur.salesCount == 1 ? 'sale' : 'sales'} · vs ${comparison.vs}',
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final s = d.current!;
    final c = d.currency;
    final tiles = <Widget>[
      _MetricTile(
        label: 'Gross profit',
        value: s.grossProfit.format(c),
        note: s.costDataComplete ? 'Net sales minus cost of goods' : 'Estimate — some items have no cost price',
        warn: !s.costDataComplete,
      ),
      _MetricTile(label: 'Expenses', value: s.expenses.format(c), note: 'Recorded in this period'),
      _MetricTile(
        label: 'Net profit (est.)',
        value: s.netProfit.format(c),
        note: 'Gross profit minus expenses',
        warn: !s.costDataComplete,
        negative: s.netProfit.isNegative,
      ),
      _MetricTile(label: 'Average sale', value: s.averageSale.format(c), note: '${s.salesCount} sales'),
      _MetricTile(
        label: 'Products',
        value: '${d.activeProducts}',
        note: d.lowStockCount + d.outOfStockCount == 0
            ? 'All stocked'
            : '${d.lowStockCount + d.outOfStockCount} need restocking',
        warn: d.lowStockCount + d.outOfStockCount > 0,
      ),
      if (d.valuationAtCost != null)
        _MetricTile(label: 'Stock value', value: d.valuationAtCost!.format(c), note: 'At cost price'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 3 : 2;
        final width = (constraints.maxWidth - Space.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.note,
    this.warn = false,
    this.negative = false,
  });

  final String label;
  final String value;
  final String note;
  final bool warn;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodySmall),
          const SizedBox(height: Space.xxs),
          MoneyText(value, style: t.titleMedium?.copyWith(color: negative ? BizColors.error : null)),
          const SizedBox(height: Space.xxs),
          Text(
            note,
            style: t.labelSmall?.copyWith(color: warn ? BizColors.warning : BizColors.textSecondary),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final max = d.topProducts.map((p) => p.revenue.minor).fold(BigInt.one, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        children: [
          for (final p in d.topProducts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Expanded(child: Text('${p.quantity} sold', style: t.bodySmall)),
                      Flexible(child: MoneyText(p.revenue.format(d.currency), style: t.titleSmall)),
                    ],
                  ),
                  const SizedBox(height: Space.xxs),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (p.revenue.minor * BigInt.from(1000) ~/ max).toInt() / 1000),
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.slow,
                    curve: Motion.curve,
                    builder: (_, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        color: BizColors.secondary,
                        backgroundColor: BizColors.secondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Skeleton(height: 72, radius: Radii.md),
      SizedBox(height: Space.md),
      Skeleton(height: 140, radius: Radii.lg),
      SizedBox(height: Space.sm),
      Row(
        children: [
          Expanded(child: Skeleton(height: 96, radius: Radii.lg)),
          SizedBox(width: Space.sm),
          Expanded(child: Skeleton(height: 96, radius: Radii.lg)),
        ],
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../expenses/expenses_screens.dart' show expenseCategories;
import '../onboarding/onboarding_screens.dart' show paymentMethodLabels;

typedef ReportRange = ({DateTime from, DateTime to});

final _reportBundleProvider = FutureProvider.autoDispose
    .family<
      ({
        ReportSummary summary,
        List<Map<String, dynamic>> products,
        List<Map<String, dynamic>> methods,
        List<Map<String, dynamic>> expenses,
      }),
      ReportRange
    >((ref, range) async {
      final bid = ref.watch(activeBusinessIdProvider);
      final api = ref.watch(apiProvider);
      final results = await Future.wait([
        api.summary(bid, from: range.from, to: range.to),
        api.report(bid, 'sales-by-product', from: range.from, to: range.to),
        api.report(bid, 'payment-methods', from: range.from, to: range.to),
        api.report(bid, 'expenses-by-category', from: range.from, to: range.to),
      ]);
      return (
        summary: results[0] as ReportSummary,
        products: results[1] as List<Map<String, dynamic>>,
        methods: results[2] as List<Map<String, dynamic>>,
        expenses: results[3] as List<Map<String, dynamic>>,
      );
    });

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late ReportRange _range = _thisMonth();

  static ReportRange _thisMonth() {
    final now = DateTime.now();
    return (from: DateTime(now.year, now.month), to: DateTime(now.year, now.month, now.day));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to),
    );
    if (picked != null) setState(() => _range = (from: picked.start, to: picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(_reportBundleProvider(_range));
    final currency = ref.watch(currentBusinessProvider).value?.currency ?? '';
    final t = Theme.of(context).textTheme;
    final fmt = DateFormat.MMMd();
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: AsyncView(
        value: bundle,
        onRetry: () => ref.invalidate(_reportBundleProvider(_range)),
        data: (r) {
          final s = r.summary;
          Widget line(String label, Money v, {bool bold = false, String? note}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: bold ? t.titleSmall : t.bodyMedium),
                      if (note != null) Text(note, style: t.labelSmall?.copyWith(color: BizColors.textSecondary)),
                    ],
                  ),
                ),
                Text(
                  v.format(currency),
                  style: (bold ? t.titleSmall! : t.bodyMedium!)
                      .copyWith(color: v.isNegative ? BizColors.error : null)
                      .tabular,
                ),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text('${fmt.format(_range.from)} – ${fmt.format(_range.to)}'),
                    ),
                    const SectionHeader('Profit & loss (operational)'),
                    AppCard(
                      child: Column(
                        children: [
                          line('Gross sales', s.grossSales, note: '${s.salesCount} sales, before discounts'),
                          line('Discounts', Money.zero - s.discounts),
                          line('Refunds', Money.zero - s.refunds),
                          const Divider(height: Space.md),
                          line('Net sales', s.netSales, bold: true),
                          line('Cost of goods sold', Money.zero - s.cogs),
                          line(
                            'Gross profit',
                            s.grossProfit,
                            bold: true,
                            note: s.costDataComplete
                                ? null
                                : 'Some items sold had no cost price, so this is overstated.',
                          ),
                          line('Expenses', Money.zero - s.expenses),
                          const Divider(height: Space.md),
                          line('Net profit (estimate)', s.netProfit, bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Prices include any configured tax. This is an operational summary, not a statutory financial statement.',
                      style: t.bodySmall,
                    ),
                    _Breakdown(
                      title: 'Sales by product',
                      empty: 'No products sold in this period.',
                      rows: [
                        for (final p in r.products)
                          (p['name'] as String, '${p['quantity']} sold', Money.parse(p['revenue'] as String)),
                      ],
                      currency: currency,
                    ),
                    _Breakdown(
                      title: 'Money received by method',
                      empty: 'No payments in this period.',
                      rows: [
                        for (final m in r.methods)
                          (
                            paymentMethodLabels[m['label']]?.$1 ?? humanize(m['label'] as String),
                            '${m['count']} payments',
                            Money.parse(m['amount'] as String),
                          ),
                      ],
                      currency: currency,
                    ),
                    _Breakdown(
                      title: 'Expenses by category',
                      empty: 'No expenses in this period.',
                      rows: [
                        for (final e in r.expenses)
                          (
                            expenseCategories[e['label']]?.$1 ?? humanize(e['label'] as String),
                            '${e['count']} entries',
                            Money.parse(e['amount'] as String),
                          ),
                      ],
                      currency: currency,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.rows, required this.currency, required this.empty});

  final String title;
  final List<(String, String, Money)> rows;
  final String currency;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        AppCard(
          padding: rows.isEmpty ? const EdgeInsets.all(Space.md) : EdgeInsets.zero,
          child: rows.isEmpty
              ? Text(empty, style: t.bodySmall)
              : Column(
                  children: [
                    for (final (i, r) in rows.indexed) ...[
                      if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
                      ListTile(
                        dense: true,
                        title: Text(r.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(r.$2),
                        trailing: Text(r.$3.format(currency), style: t.titleSmall!.tabular),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

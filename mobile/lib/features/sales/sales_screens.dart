import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../onboarding/onboarding_screens.dart' show paymentMethodLabels;
import '../products/product_providers.dart';

final salesProvider = FutureProvider.autoDispose.family<PageResult<SaleSummary>, String>((ref, q) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).sales(bid, q: q.isEmpty ? null : q);
});

final receiptProvider = FutureProvider.autoDispose.family<Receipt, String>((ref, saleId) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).receipt(bid, saleId);
});

final saleProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, saleId) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).sale(bid, saleId);
});

(String, Tone) saleStatus(String status) => switch (status) {
  'completed' => ('Completed', Tone.success),
  'partially_refunded' => ('Part refunded', Tone.warning),
  'refunded' => ('Refunded', Tone.error),
  _ => (humanize(status), Tone.neutral),
};

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider(_q));
    final currency = ref.watch(currentBusinessProvider).value?.currency ?? '';
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: Column(
        children: [
          PageBody(
            child: TextField(
              onSubmitted: (v) => setState(() => _q = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Find a receipt number',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(salesProvider(_q).future),
              child: AsyncView(
                value: sales,
                onRetry: () => ref.invalidate(salesProvider(_q)),
                data: (page) => page.items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: Space.xl),
                          EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No sales yet',
                            message: 'Completed sales and their receipts appear here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(Space.page),
                        itemCount: page.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                        itemBuilder: (_, i) {
                          final s = page.items[i];
                          final (label, tone) = saleStatus(s.status);
                          return AppCard(
                            onTap: () => context.push('/sales/${s.id}'),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.receiptNumber, style: t.titleSmall),
                                      Text(DateFormat.MMMd().add_jm().format(s.createdAt), style: t.bodySmall),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    MoneyText(s.total.format(currency), style: t.titleSmall),
                                    const SizedBox(height: 2),
                                    StatusChip(label, tone: tone),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.saleId, this.justCompleted = false});

  final String saleId;
  final bool justCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptProvider(saleId));
    final business = ref.watch(currentBusinessProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        leading: justCompleted ? CloseButton(onPressed: () => context.go('/sell')) : null,
      ),
      body: AsyncView(
        value: receipt,
        onRetry: () => ref.invalidate(receiptProvider(saleId)),
        data: (r) => ListView(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (justCompleted) const _SaleSuccessBanner(),
                  _ReceiptCard(receipt: r),
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: receiptAsText(r)));
                      showMessage(context, 'Receipt copied — paste it into WhatsApp or SMS');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy receipt to share'),
                  ),
                  if ((business?.can(Perm.salesRefund) ?? false) && r.status != 'refunded') ...[
                    const SizedBox(height: Space.sm),
                    TextButton.icon(
                      onPressed: () => _showReturnSheet(context, ref, business!, saleId),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Return items / refund'),
                    ),
                  ],
                  if (justCompleted) ...[
                    const SizedBox(height: Space.sm),
                    PrimaryButton(label: 'New sale', icon: Icons.add_rounded, onPressed: () => context.go('/sell')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleSuccessBanner extends StatelessWidget {
  const _SaleSuccessBanner();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0.6, end: 1),
      duration: Motion.slow,
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Semantics(
          liveRegion: true,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: const BoxDecoration(color: BizColors.successContainer, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: BizColors.success, size: 36),
              ),
              const SizedBox(height: Space.xs),
              Text('Sale completed', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final t = Theme.of(context).textTheme;
    final c = r.currency;
    final (label, tone) = saleStatus(r.status);
    Widget row(String a, String b, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(a, style: style)),
          Text(b, style: (style ?? t.bodyMedium!).tabular),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.logoUrl != null) ...[
            Center(
              child: Image.network(
                r.logoUrl!,
                height: 56,
                fit: BoxFit.contain,
                semanticLabel: '${r.businessName} logo',
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: Space.xs),
          ],
          Text(r.businessName, style: t.titleLarge, textAlign: TextAlign.center),
          if (r.businessAddress != null) Text(r.businessAddress!, style: t.bodySmall, textAlign: TextAlign.center),
          if (r.businessPhone != null) Text(r.businessPhone!, style: t.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(child: Text('Receipt ${r.receiptNumber}', style: t.titleSmall)),
              StatusChip(label, tone: tone),
            ],
          ),
          Text('${DateFormat.yMMMd().add_jm().format(r.issuedAt)} · Served by ${r.cashierName}', style: t.bodySmall),
          if (r.customerName != null) Text('Customer: ${r.customerName}', style: t.bodySmall),
          const Divider(height: Space.lg),
          for (final l in r.lines) ...[
            Text(l.productName, style: t.bodyMedium),
            row(
              '  ${l.quantity} × ${l.unitPrice.format(c, showCurrency: false)}',
              l.lineTotal.format(c, showCurrency: false),
              style: t.bodySmall,
            ),
            if (!l.discount.isZero)
              row('  Discount', '-${l.discount.format(c, showCurrency: false)}', style: t.bodySmall),
            const SizedBox(height: Space.xxs),
          ],
          const Divider(height: Space.lg),
          row('Subtotal', r.subtotal.format(c)),
          if (!r.discountTotal.isZero) row('Discount', '-${r.discountTotal.format(c)}'),
          row('Total', r.total.format(c), style: t.titleMedium),
          if (!r.taxTotal.isZero) row('Includes tax (${r.taxRatePercent}%)', r.taxTotal.format(c), style: t.bodySmall),
          const SizedBox(height: Space.xs),
          for (final p in r.payments.where((p) => p.kind == 'payment'))
            row(
              'Paid · ${paymentMethodLabels[p.method]?.$1 ?? humanize(p.method)}',
              p.amount.format(c),
              style: t.bodySmall,
            ),
          if (!r.changeDue.isZero) row('Cash received', r.amountPaid.format(c), style: t.bodySmall),
          if (!r.changeDue.isZero) row('Change', r.changeDue.format(c), style: t.bodySmall),
          if (!r.refundedTotal.isZero)
            row('Refunded', '-${r.refundedTotal.format(c)}', style: t.bodySmall?.copyWith(color: BizColors.error)),
          if (r.footer != null) ...[
            const SizedBox(height: Space.md),
            Text(r.footer!, style: t.bodySmall, textAlign: TextAlign.center),
          ],
          const SizedBox(height: Space.md),
          Text(
            'Powered by STANZ BizFlow',
            style: t.labelSmall?.copyWith(color: BizColors.textDisabled),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String receiptAsText(Receipt r) {
  final c = r.currency;
  final b = StringBuffer()
    ..writeln(r.businessName)
    ..writeln('Receipt ${r.receiptNumber}')
    ..writeln(DateFormat.yMMMd().add_jm().format(r.issuedAt))
    ..writeln('');
  for (final l in r.lines) {
    b.writeln(
      '${l.productName}  ${l.quantity} x ${l.unitPrice.format(c, showCurrency: false)} = ${l.lineTotal.format(c, showCurrency: false)}',
    );
  }
  b
    ..writeln('')
    ..writeln('TOTAL: ${r.total.format(c)}');
  if (!r.refundedTotal.isZero) b.writeln('Refunded: ${r.refundedTotal.format(c)}');
  if (r.footer != null) b.writeln(r.footer);
  return b.toString();
}

Future<void> _showReturnSheet(BuildContext context, WidgetRef ref, Business business, String saleId) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReturnSheet(business: business, saleId: saleId),
    );

class _ReturnSheet extends ConsumerStatefulWidget {
  const _ReturnSheet({required this.business, required this.saleId});

  final Business business;
  final String saleId;

  @override
  ConsumerState<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<_ReturnSheet> {
  final Map<String, Quantity> _qty = {};
  final _reason = TextEditingController();
  bool _restock = true;
  bool _busy = false;
  String? _error;
  // One idempotency key per return attempt, reused if the request is retried.
  final _reference = const Uuid().v4().replaceAll('-', '');

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lines = _qty.entries.where((e) => e.value.isPositive).toList();
    if (lines.isEmpty) return setState(() => _error = 'Choose at least one item to return');
    if (_reason.text.trim().length < 3) return setState(() => _error = 'Give a reason for the return');
    if (!await confirm(
      context,
      title: 'Confirm return',
      message: 'This records a refund and cannot be undone.',
      confirmLabel: 'Record return',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).returnItems(widget.business.id, widget.saleId, {
        'client_reference': _reference,
        'lines': [
          for (final e in lines) {'sale_item_id': e.key, 'quantity': e.value.toString()},
        ],
        'reason': _reason.text.trim(),
        'restock': _restock,
        'refund_method': 'cash',
      });
      ref.invalidate(receiptProvider(widget.saleId));
      ref.invalidate(saleProvider(widget.saleId));
      ref.invalidate(salesProvider);
      invalidateCatalog(ref);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Return recorded');
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = ref.watch(saleProvider(widget.saleId));
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, MediaQuery.viewInsetsOf(context).bottom + Space.lg),
      child: AsyncView(
        value: sale,
        loading: const Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        data: (s) {
          final items = (s['items'] as List).cast<Map<String, dynamic>>().map(SaleLine.fromJson).toList();
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Return items', style: t.titleLarge),
                const SizedBox(height: Space.sm),
                for (final item in items)
                  if (item.quantity - item.quantityReturned case final left when left.isPositive)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.productName),
                      subtitle: Text('$left of ${item.quantity} can be returned'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Less',
                            onPressed: (_qty[item.id]?.isPositive ?? false)
                                ? () => setState(() => _qty[item.id] = _qty[item.id]! - Quantity.whole(1))
                                : null,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          Text('${_qty[item.id] ?? Quantity.whole(0)}', style: t.titleMedium),
                          IconButton(
                            tooltip: 'More',
                            onPressed: (_qty[item.id] ?? Quantity.whole(0)) + Quantity.whole(1) <= left
                                ? () => setState(
                                    () => _qty[item.id] = (_qty[item.id] ?? Quantity.whole(0)) + Quantity.whole(1),
                                  )
                                : null,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _reason,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Faulty charging port'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _restock,
                  onChanged: (v) => setState(() => _restock = v),
                  title: const Text('Put items back in stock'),
                  subtitle: const Text('Turn off if the item is damaged and cannot be resold.'),
                ),
                if (_error != null) Text(_error!, style: const TextStyle(color: BizColors.error)),
                const SizedBox(height: Space.md),
                PrimaryButton(label: 'Record return', loading: _busy, onPressed: _submit),
              ],
            ),
          );
        },
      ),
    );
  }
}

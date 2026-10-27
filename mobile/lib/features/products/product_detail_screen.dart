import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import 'product_providers.dart';
import 'product_widgets.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref, Business b, Product p) async {
    final archiving = p.isActive;
    if (archiving &&
        !await confirm(
          context,
          title: 'Archive ${p.name}?',
          message: 'It will be hidden from the catalogue and cannot be sold. Sales history is kept. You can restore it later.',
          confirmLabel: 'Archive',
        )) {
      return;
    }
    try {
      await ref.read(apiProvider).setArchived(b.id, p.id, archived: archiving);
      invalidateCatalog(ref);
      if (context.mounted) showMessage(context, archiving ? 'Product archived' : 'Product restored');
    } on ApiError catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));
    final business = ref.watch(currentBusinessProvider).value;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          if (business?.can(Perm.productsManage) ?? false) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/products/$productId/edit'),
            ),
            if (product.value case final p?)
              PopupMenuButton<String>(
                onSelected: (_) => _toggleArchive(context, ref, business!, p),
                itemBuilder: (_) => [PopupMenuItem(value: 'archive', child: Text(p.isActive ? 'Archive' : 'Restore'))],
              ),
          ],
        ],
      ),
      body: AsyncView(
        value: product,
        onRetry: () => ref.invalidate(productProvider(productId)),
        data: (p) {
          final currency = business?.currency ?? '';
          final margin = p.costPrice == null || p.costPrice!.isZero ? null : p.sellingPrice - p.costPrice!;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(productMovementsProvider(productId));
              ref.invalidate(productProvider(productId));
              await ref.read(productProvider(productId).future);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              children: [
                PageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ProductAvatar(name: p.name, size: 64),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: t.titleLarge),
                                if (p.variantLine.isNotEmpty) Text(p.variantLine, style: t.bodySmall),
                                const SizedBox(height: Space.xxs),
                                Wrap(
                                  spacing: Space.xs,
                                  children: [
                                    StatusChip(p.stockStatus.label, tone: stockTone(p.stockStatus)),
                                    if (!p.isActive) const StatusChip('Archived'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(label: 'Selling price', value: p.sellingPrice.format(currency)),
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: _Stat(
                              label: 'In stock',
                              value: p.trackStock ? '${p.quantityOnHand} ${p.unit}' : 'Not tracked',
                            ),
                          ),
                        ],
                      ),
                      if (p.costPrice != null) ...[
                        const SizedBox(height: Space.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(label: 'Cost price', value: p.costPrice!.format(currency)),
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: _Stat(
                                label: 'Margin per unit',
                                value: margin == null ? 'Add a cost price' : margin.format(currency),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if ((business?.can(Perm.inventoryAdjust) ?? false) && p.trackStock && p.isActive) ...[
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                label: 'Receive stock',
                                icon: Icons.add_rounded,
                                onPressed: () => showStockSheet(context, ref, business!, p, type: 'receipt'),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => showStockSheet(context, ref, business!, p, type: 'count'),
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('Adjust'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SectionHeader('Details'),
                      AppCard(
                        child: Column(
                          children: [
                            for (final (k, v) in [
                              ('SKU', p.sku),
                              ('Barcode', p.barcode),
                              ('Reorder alert', p.trackStock ? '${p.reorderLevel} ${p.unit}' : null),
                              ('Condition', p.attributes['condition'] as String?),
                              (
                                'Warranty',
                                p.attributes['warranty_months'] == null
                                    ? null
                                    : '${p.attributes['warranty_months']} months',
                              ),
                              ('IMEI / serial', p.attributes['imei'] as String?),
                              ('Description', p.description),
                            ])
                              if (v != null && v.isNotEmpty) _DetailRow(label: k, value: v),
                            _DetailRow(label: 'Last updated', value: DateFormat.yMMMd().add_jm().format(p.updatedAt)),
                          ],
                        ),
                      ),
                      if (business?.can(Perm.inventoryView) ?? false) ...[
                        const SectionHeader('Stock history'),
                        _MovementList(productId: p.id, unit: p.unit),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.xxs),
        MoneyText(value),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

const _reasonLabels = {
  'opening': 'Opening stock',
  'receipt': 'Stock received',
  'sale': 'Sold',
  'return': 'Customer return',
  'adjustment': 'Correction',
  'damage': 'Damaged / lost',
  'count': 'Stock count',
};

class _MovementList extends ConsumerWidget {
  const _MovementList({required this.productId, required this.unit});

  final String productId;
  final String unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moves = ref.watch(productMovementsProvider(productId));
    return AsyncView(
      value: moves,
      loading: const Skeleton(height: 120, radius: Radii.lg),
      data: (page) => page.items.isEmpty
          ? Text('No stock changes yet.', style: Theme.of(context).textTheme.bodySmall)
          : AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, m) in page.items.take(20).indexed) ...[
                    if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
                    ListTile(
                      dense: true,
                      title: Text(_reasonLabels[m.reason] ?? humanize(m.reason)),
                      subtitle: Text([DateFormat.MMMd().add_jm().format(m.createdAt), ?m.note].join(' · ')),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${m.change.isPositive ? '+' : ''}${m.change}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: m.change.isPositive ? BizColors.success : BizColors.error,
                            ),
                          ),
                          Text('${m.after} $unit', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Bottom sheet for receiving, counting, correcting and writing off stock.
Future<void> showStockSheet(
  BuildContext context,
  WidgetRef ref,
  Business business,
  Product product, {
  required String type,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => _StockSheet(business: business, product: product, initialType: type),
);

class _StockSheet extends ConsumerStatefulWidget {
  const _StockSheet({required this.business, required this.product, required this.initialType});

  final Business business;
  final Product product;
  final String initialType;

  @override
  ConsumerState<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<_StockSheet> {
  late String _type = widget.initialType;
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = Quantity.tryParse(_qty.text);
    if (q == null || (!q.isPositive && _type != 'count')) {
      setState(() => _error = 'Enter a quantity greater than zero');
      return;
    }
    if (_type != 'receipt' && _note.text.trim().isEmpty) {
      setState(() => _error = 'Add a short reason so the change can be audited');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).adjustStock(widget.business.id, widget.product.id, {
        'type': _type,
        if (_type == 'count') 'counted_quantity': q.toString() else 'quantity': q.toString(),
        if (_type == 'receipt' && Money.tryParse(_cost.text) != null) 'unit_cost': Money.parse(_cost.text).toApi(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      invalidateCatalog(ref);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Stock updated');
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = widget.product;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, MediaQuery.viewInsetsOf(context).bottom + Space.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Update stock', style: t.titleLarge),
            Text('${p.name} · currently ${p.quantityOnHand} ${p.unit}', style: t.bodySmall),
            const SizedBox(height: Space.md),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'receipt', label: Text('Receive')),
                ButtonSegment(value: 'count', label: Text('Count')),
                ButtonSegment(value: 'damage', label: Text('Damaged')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
              decoration: InputDecoration(
                labelText: switch (_type) {
                  'receipt' => 'Quantity received',
                  'count' => 'Quantity counted on the shelf',
                  _ => 'Quantity damaged or lost',
                },
                suffixText: p.unit,
              ),
            ),
            if (_type == 'receipt' && widget.business.can(Perm.productsViewCost)) ...[
              const SizedBox(height: Space.md),
              TextField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cost per unit (optional)',
                  prefixText: '${widget.business.currency} ',
                  helperText: 'Updates the average cost used for profit.',
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: _type == 'receipt' ? 'Supplier / note (optional)' : 'Reason'),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(_error!, style: const TextStyle(color: BizColors.error)),
            ],
            const SizedBox(height: Space.lg),
            PrimaryButton(label: 'Save', loading: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

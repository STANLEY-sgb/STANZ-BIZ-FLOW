import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/offline_providers.dart';
import '../../data/models.dart';
import '../onboarding/onboarding_screens.dart' show paymentMethodLabels;
import '../products/product_providers.dart';
import '../products/product_widgets.dart';
import 'cart.dart';

/// Point of sale: search or scan, tap to add, review the cart, take payment.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v));
  }

  /// Hardware/Bluetooth barcode scanners type the code and press Enter.
  Future<void> _onSubmitted(Business b, String code) async {
    if (code.trim().isEmpty) return;
    Product? p;
    try {
      p = await ref.read(apiProvider).lookup(b.id, code.trim());
    } on ApiError catch (e) {
      // Offline: use the saved catalogue. Otherwise it is not an exact code, so keep it as a search.
      if (e.isNetwork) p = await ref.read(offlineSyncProvider).cachedByCode(b.id, code.trim());
    }
    if (p == null || !mounted) return;
    _add(b, p);
    _search.clear();
    _onSearch('');
  }

  void _add(Business b, Product p) {
    final inCart = ref.read(cartProvider).quantityOf(p.id);
    if (b.enforceStock && p.trackStock && !(p.quantityOnHand > inCart)) {
      showMessage(context, 'No more ${p.name} in stock', error: true);
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(cartProvider.notifier).add(p);
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(currentBusinessProvider);
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          const SyncBadge(),
          IconButton(
            tooltip: 'Sales history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/sales'),
          ),
        ],
      ),
      body: AsyncView(
        value: business,
        data: (b) {
          if (!b.can(Perm.salesCreate)) {
            return const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Selling is not enabled for your role',
              message: 'Ask the business owner to give you cashier access.',
            );
          }
          final catalog = ref.watch(posCatalogProvider(_query));
          return Column(
            children: [
              PageBody(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  onSubmitted: (v) => _onSubmitted(b, v),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search or scan a barcode',
                    prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                  ),
                ),
              ),
              if (catalog.value case final c? when c.offline) _OfflineBanner(syncedAt: c.syncedAt),
              const SizedBox(height: Space.xs),
              Expanded(
                child: AsyncView(
                  value: catalog,
                  onRetry: () => ref.invalidate(posCatalogProvider(_query)),
                  data: (page) => page.items.isEmpty
                      ? EmptyState(
                          icon: page.offline ? Icons.cloud_off_rounded : Icons.search_off_rounded,
                          title: page.offline
                              ? 'No saved products'
                              : (_query.isEmpty ? 'No products to sell yet' : 'No matches'),
                          message: page.offline
                              ? 'Connect once so BizFlow can save your products on this phone for offline selling.'
                              : (_query.isEmpty
                                    ? 'Add products first, then come back to sell.'
                                    : 'Try another name or code.'),
                          actionLabel: !page.offline && _query.isEmpty && b.can(Perm.productsManage)
                              ? 'Add a product'
                              : null,
                          onAction: () => context.push('/products/new'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, 120),
                          itemCount: page.items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                          itemBuilder: (_, i) {
                            final p = page.items[i];
                            final inCart = cart.quantityOf(p.id);
                            return ProductTile(
                              product: p,
                              currency: b.currency,
                              onTap: () => _add(b, p),
                              trailing: inCart.isPositive
                                  ? StatusChip('$inCart in cart', tone: Tone.brand)
                                  : const Icon(
                                      Icons.add_circle_rounded,
                                      color: BizColors.primary,
                                      semanticLabel: 'Add to cart',
                                    ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: Motion.normal,
        transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, child: child),
        child: cart.isEmpty || !business.hasValue
            ? const SizedBox.shrink()
            : _CartBar(cart: cart, currency: business.requireValue.currency),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.currency});

  final Cart cart;
  final String currency;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.sm),
      child: Material(
        color: BizColors.navy,
        borderRadius: Radii.card,
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/sell/cart'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
                  decoration: BoxDecoration(color: BizColors.primary, borderRadius: Radii.chip),
                  child: Text(
                    '${cart.itemCount}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    cart.total.format(currency),
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Colors.white).tabular,
                  ),
                ),
                const Text(
                  'Review sale',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Cart review and checkout.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _method;
  final _tendered = TextEditingController();
  final _reference = TextEditingController();
  final _discount = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tendered.dispose();
    _reference.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _complete(Business b, Cart cart) async {
    final method = _method ?? b.paymentMethods.first;
    final tendered = method == 'cash' ? (Money.tryParse(_tendered.text) ?? cart.total) : cart.total;
    if (tendered < cart.total) {
      setState(() => _error = 'Amount received is less than the total');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(cartProvider.notifier);
    controller.beginCheckout();
    final request = ref
        .read(cartProvider)
        .toSaleRequest(
          payments: [
            (
              method: method,
              amount: tendered,
              reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            ),
          ],
        );
    try {
      final sale = await ref.read(apiProvider).createSale(b.id, request);
      unawaited(HapticFeedback.mediumImpact());
      controller.clear();
      invalidateCatalog(ref);
      if (mounted) context.pushReplacement('/sales/${sale['id']}?new=1');
    } on ApiError catch (e) {
      if (e.isNetwork) {
        await _saveOffline(b, cart, request);
        return;
      }
      setState(() => _error = e.message);
      if (e.code == 'price_changed' || e.code == 'insufficient_stock') invalidateCatalog(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// No connection: queue the sale under the SAME idempotency key. If the first request actually
  /// reached the server, the later sync is answered as a duplicate, so nothing is recorded twice.
  Future<void> _saveOffline(Business b, Cart cart, Map<String, Object?> request) async {
    try {
      final userId = await ref.read(currentUserIdProvider.future);
      if (userId == null) throw StateError('signed out');
      await ref
          .read(offlineSyncProvider)
          .enqueueSale(
            businessId: b.id,
            userId: userId,
            deviceId: await ref.read(deviceIdProvider.future),
            saleRequest: request,
            previewTotal: cart.total,
            summary: describeCart(cart),
          );
    } on Object {
      if (mounted) setState(() => _error = 'Could not save the sale on this phone. Please try again.');
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    ref.read(cartProvider.notifier).clear();
    invalidateCatalog(ref);
    if (!mounted) return;
    showMessage(context, 'No connection. Sale saved on this phone and will sync automatically.');
    context.pushReplacement('/sync');
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final business = ref.watch(currentBusinessProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review sale')),
      body: AsyncView(
        value: business,
        data: (b) {
          if (cart.isEmpty) {
            return EmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'Cart is empty',
              message: 'Add products to start a sale.',
              actionLabel: 'Back to products',
              onAction: () => context.pop(),
            );
          }
          final method = _method ?? b.paymentMethods.first;
          final tendered = Money.tryParse(_tendered.text);
          final change = method == 'cash' && tendered != null && tendered > cart.total ? tendered - cart.total : null;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, line) in cart.lines.indexed) ...[
                            if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
                            _CartLineRow(line: line, currency: b.currency, enforceStock: b.enforceStock),
                          ],
                        ],
                      ),
                    ),
                    if (b.can(Perm.salesDiscount)) ...[
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _discount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        onChanged: (v) => ref.read(cartProvider.notifier).setDiscount(Money.tryParse(v)),
                        decoration: InputDecoration(labelText: 'Discount (optional)', prefixText: '${b.currency} '),
                      ),
                    ],
                    const SectionHeader('Payment'),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final m in b.paymentMethods)
                          ChoiceChip(
                            avatar: Icon(paymentMethodLabels[m]?.$2 ?? Icons.payments_rounded, size: 18),
                            label: Text(paymentMethodLabels[m]?.$1 ?? humanize(m)),
                            selected: method == m,
                            onSelected: (_) => setState(() => _method = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    if (method == 'cash')
                      TextField(
                        controller: _tendered,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Cash received',
                          hintText: cart.total.format(b.currency, showCurrency: false),
                          prefixText: '${b.currency} ',
                          helperText: 'Leave empty if the customer paid the exact amount.',
                        ),
                      )
                    else
                      TextField(
                        controller: _reference,
                        decoration: const InputDecoration(
                          labelText: 'Transaction ID (optional)',
                          hintText: 'e.g. mobile money reference',
                        ),
                      ),
                    const SizedBox(height: Space.lg),
                    AppCard(
                      color: BizColors.surfaceMuted,
                      child: Column(
                        children: [
                          _TotalRow('Subtotal', cart.subtotal.format(b.currency)),
                          if (!cart.discount.isZero) _TotalRow('Discount', '- ${cart.discount.format(b.currency)}'),
                          const Divider(height: Space.lg),
                          _TotalRow('Total', cart.total.format(b.currency), emphasis: true),
                          if (change != null) _TotalRow('Change to give', change.format(b.currency)),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Final totals and stock are confirmed by the server when you complete the sale.',
                      style: t.bodySmall,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, style: const TextStyle(color: BizColors.error)),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    PrimaryButton(
                      label: 'Complete sale · ${cart.total.format(b.currency)}',
                      icon: Icons.check_rounded,
                      loading: _busy,
                      onPressed: () => _complete(b, cart),
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

class _CartLineRow extends ConsumerWidget {
  const _CartLineRow({required this.line, required this.currency, required this.enforceStock});

  final CartLine line;
  final String currency;
  final bool enforceStock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cart = ref.read(cartProvider.notifier);
    final p = line.product;
    final atLimit = enforceStock && p.trackStock && !(p.quantityOnHand > line.quantity);
    return Padding(
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('${p.sellingPrice.format(currency)} each', style: t.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove one',
            icon: const Icon(Icons.remove_circle_outline_rounded),
            onPressed: () => cart.decrement(p.id),
          ),
          Text('${line.quantity}', style: t.titleMedium!.tabular),
          IconButton(
            tooltip: 'Add one',
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: BizColors.primary,
            onPressed: atLimit ? null : () => cart.increment(p.id),
          ),
          SizedBox(
            width: 100,
            child: Text(
              line.total.format(currency, showCurrency: false),
              textAlign: TextAlign.end,
              style: t.titleSmall!.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = emphasis ? t.titleLarge : t.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style!.tabular),
        ],
      ),
    );
  }
}

String describeCart(Cart cart) => cart.lines
    .map((l) => l.quantity == Quantity.whole(1) ? l.product.name : '${l.quantity}× ${l.product.name}')
    .join(', ');

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.syncedAt});

  final DateTime? syncedAt;

  @override
  Widget build(BuildContext context) => PageBody(
    padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, 0),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(color: BizColors.warningContainer, borderRadius: Radii.control),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: BizColors.warning, size: 20),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                syncedAt == null
                    ? 'Offline. Showing saved products; stock may be out of date.'
                    : 'Offline. Products and stock as of ${DateFormat.MMMd().add_jm().format(syncedAt!)}. '
                          'Sales will sync when you reconnect.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: BizColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// App-bar indicator of sales waiting to sync (or needing review).
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unresolved = ref.watch(unresolvedSalesProvider).value ?? const [];
    final running = ref.watch(syncControllerProvider.select((s) => s.running));
    final rejected = unresolved.where((s) => s.state == 'rejected').length;
    if (unresolved.isEmpty && !running) return const SizedBox.shrink();
    final label = rejected > 0 ? '$rejected sales need review' : '${unresolved.length} sales waiting to sync';
    return IconButton(
      tooltip: running ? 'Syncing…' : label,
      onPressed: () => context.push('/sync'),
      icon: Badge(
        isLabelVisible: unresolved.isNotEmpty,
        label: Text('${unresolved.length}'),
        backgroundColor: rejected > 0 ? BizColors.error : BizColors.primary,
        child: Icon(running ? Icons.sync_rounded : Icons.cloud_upload_outlined),
      ),
    );
  }
}

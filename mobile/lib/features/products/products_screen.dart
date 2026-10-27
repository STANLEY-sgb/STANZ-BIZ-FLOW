import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import 'product_import_screen.dart';
import 'product_providers.dart';
import 'product_widgets.dart';

/// Shared catalogue browser used by the Products tab and the Inventory tab.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key, this.inventoryMode = false});

  /// Inventory mode opens on low-stock items and emphasises stock actions.
  final bool inventoryMode;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  late ProductQuery _query = widget.inventoryMode
      ? (q: '', categoryId: null, stock: 'low_stock', limit: 40)
      : defaultProductQuery;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _query = (q: value, categoryId: _query.categoryId, stock: _query.stock, limit: 40));
    });
  }

  void _setFilter({String? categoryId, String? stock, bool clearCategory = false, bool clearStock = false}) =>
      setState(() {
        _query = (
          q: _query.q,
          categoryId: clearCategory ? null : (categoryId ?? _query.categoryId),
          stock: clearStock ? null : (stock ?? _query.stock),
          limit: 40,
        );
      });

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(currentBusinessProvider).value;
    final canManage = business?.can(Perm.productsManage) ?? false;
    final products = ref.watch(productListProvider(_query));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final currency = business?.currency ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.inventoryMode ? 'Inventory' : 'Products'),
        actions: [
          if (!widget.inventoryMode)
            PopupMenuButton<String>(
              tooltip: 'Import or export',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => v == 'import' ? context.push('/products/import') : exportProducts(context, ref),
              itemBuilder: (_) => [
                if (canManage)
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Import from file')),
                  ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(leading: Icon(Icons.ios_share_rounded), title: Text('Export to CSV')),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: canManage && !widget.inventoryMode
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/products/new'),
              backgroundColor: BizColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            )
          : null,
      body: Column(
        children: [
          PageBody(
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name, SKU or barcode',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.xs),
              children: [
                for (final s in [StockStatus.lowStock, StockStatus.outOfStock])
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: _query.stock == s.api,
                      onSelected: (on) => on ? _setFilter(stock: s.api) : _setFilter(clearStock: true),
                    ),
                  ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: FilterChip(
                      label: Text('${c.name} (${c.productCount})'),
                      selected: _query.categoryId == c.id,
                      onSelected: (on) => on ? _setFilter(categoryId: c.id) : _setFilter(clearCategory: true),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(productListProvider(_query).future),
              child: AsyncView(
                value: products,
                onRetry: () => ref.invalidate(productListProvider(_query)),
                data: (page) {
                  if (page.items.isEmpty) return _empty(canManage);
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, 96),
                    itemCount: page.items.length + (page.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                    itemBuilder: (context, i) {
                      if (i == page.items.length) {
                        return TextButton(
                          onPressed: () => setState(
                            () => _query = (
                              q: _query.q,
                              categoryId: _query.categoryId,
                              stock: _query.stock,
                              limit: _query.limit + 40,
                            ),
                          ),
                          child: Text('Show more (${page.total - page.items.length} remaining)'),
                        );
                      }
                      final p = page.items[i];
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
                          child: ProductTile(
                            product: p,
                            currency: currency,
                            onTap: () => context.push('/products/${p.id}'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool canManage) {
    final filtered = _query.q.isNotEmpty || _query.categoryId != null || _query.stock != null;
    if (filtered) {
      return ListView(
        children: const [
          SizedBox(height: Space.xl),
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'Try a different search or clear the filters.',
          ),
        ],
      );
    }
    return ListView(
      children: [
        const SizedBox(height: Space.xl),
        EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No products yet',
          message: 'Add the items you sell so you can track stock and record sales quickly.',
          actionLabel: canManage ? 'Add your first product' : null,
          onAction: canManage ? () => context.push('/products/new') : null,
        ),
      ],
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../data/local/offline_providers.dart';
import '../../data/models.dart';

typedef ProductQuery = ({String q, String? categoryId, String? stock, int limit});

const defaultProductQuery = (q: '', categoryId: null, stock: null, limit: 40) as ProductQuery;

final productListProvider = FutureProvider.autoDispose.family<PageResult<Product>, ProductQuery>((ref, query) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref
      .watch(apiProvider)
      .products(
        bid,
        q: query.q.trim().isEmpty ? null : query.q.trim(),
        categoryId: query.categoryId,
        stock: query.stock,
        limit: query.limit,
      );
});

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).categories(bid);
});

final productProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).product(bid, id);
});

final productMovementsProvider = FutureProvider.autoDispose.family<PageResult<StockMovement>, String>((ref, id) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).movements(bid, productId: id);
});

typedef PosCatalog = ({List<Product> items, bool offline, DateTime? syncedAt});

/// Products for the till: live from the server, or the last-synced local copy when offline.
final posCatalogProvider = FutureProvider.autoDispose.family<PosCatalog, String>((ref, q) async {
  final bid = ref.watch(activeBusinessIdProvider);
  try {
    final page = await ref.watch(apiProvider).products(bid, q: q.trim().isEmpty ? null : q.trim(), limit: 40);
    return (items: page.items, offline: false, syncedAt: null);
  } on ApiError catch (e) {
    if (!e.isNetwork) rethrow;
    final offline = ref.read(offlineSyncProvider);
    return (items: await offline.searchCached(bid, q), offline: true, syncedAt: await offline.productsSyncedAt(bid));
  }
});

/// Call after any product or stock change so every list and detail view refreshes.
void invalidateCatalog(WidgetRef ref) {
  ref.invalidate(productListProvider);
  ref.invalidate(posCatalogProvider);
  ref.invalidate(productProvider);
  ref.invalidate(productMovementsProvider);
  ref.invalidate(categoriesProvider);
}

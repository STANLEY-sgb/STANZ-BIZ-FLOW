import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
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

/// Call after any product or stock change so every list and detail view refreshes.
void invalidateCatalog(WidgetRef ref) {
  ref.invalidate(productListProvider);
  ref.invalidate(productProvider);
  ref.invalidate(productMovementsProvider);
  ref.invalidate(categoriesProvider);
}

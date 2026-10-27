import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../models.dart';
import 'local_db.dart';

typedef Json = Map<String, dynamic>;

/// Outcome of one sync pass, for UI feedback.
class SyncReport {
  const SyncReport({this.accepted = 0, this.duplicates = 0, this.rejected = 0, this.failed = false, this.error});

  final int accepted;
  final int duplicates;
  final int rejected;

  /// True when the batch could not be delivered (offline, server down, access revoked).
  final bool failed;
  final ApiError? error;

  bool get changedServerData => accepted > 0;
}

/// Offline catalogue cache and the durable queue of sales recorded without a connection.
///
/// Policy (see docs/OFFLINE_SYNC.md): every queued sale keeps one idempotency key
/// for life; the server validates each one exactly like an online sale and answers
/// accepted / duplicate / rejected. Rejected sales are never silently dropped.
class OfflineSync {
  OfflineSync({required this.db, required this.client, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final LocalDb db;
  final ApiClient client;
  final DateTime Function() _now;

  static const batchSize = 25;
  static const _keepAcknowledged = Duration(days: 7);

  /// Bounded exponential backoff: 5 s, 10 s, 20 s … capped at 10 minutes.
  static Duration backoff(int attempts) =>
      Duration(seconds: math.min(5 * math.pow(2, math.max(0, attempts - 1)).toInt(), 600));

  // --- Business profile cache --------------------------------------------------

  Future<void> cacheBusiness(Json json) => db.writeValue('business:${json['id']}', jsonEncode(json));

  Future<Business?> cachedBusiness(String businessId) async {
    final raw = await db.readValue('business:$businessId');
    return raw == null ? null : Business.fromJson(jsonDecode(raw) as Json);
  }

  // --- Product cache -------------------------------------------------------------

  /// Downloads the full active catalogue (paged) and replaces the local copy atomically.
  Future<int> refreshProducts(String businessId) async {
    final now = _now();
    final rows = <CachedProductsCompanion>[];
    var offset = 0;
    while (true) {
      final page = await client.get<Json>('/businesses/$businessId/products', query: {'limit': 100, 'offset': offset});
      final items = (page['items'] as List).cast<Json>();
      rows.addAll(items.map((j) => _row(businessId, j, now)));
      offset += items.length;
      if (items.isEmpty || offset >= (page['total'] as int)) break;
    }
    await db.replaceProducts(businessId, rows);
    await db.writeValue('products_synced:$businessId', now.toUtc().toIso8601String());
    return rows.length;
  }

  static CachedProductsCompanion _row(String businessId, Json j, DateTime syncedAt) => CachedProductsCompanion.insert(
    businessId: businessId,
    id: j['id'] as String,
    nameLower: (j['name'] as String).toLowerCase(),
    sku: Value(j['sku'] as String?),
    barcode: Value(j['barcode'] as String?),
    isActive: j['is_active'] as bool,
    json: jsonEncode(j),
    syncedAt: syncedAt,
  );

  Future<DateTime?> productsSyncedAt(String businessId) async {
    final raw = await db.readValue('products_synced:$businessId');
    return raw == null ? null : DateTime.parse(raw).toLocal();
  }

  Future<List<Product>> searchCached(String businessId, String query) async =>
      (await db.searchProducts(businessId, query)).map((r) => Product.fromJson(jsonDecode(r.json) as Json)).toList();

  Future<Product?> cachedByCode(String businessId, String code) async {
    final row = await db.productByCode(businessId, code);
    return row == null ? null : Product.fromJson(jsonDecode(row.json) as Json);
  }

  // --- Queue -----------------------------------------------------------------------

  /// Stores a sale for later delivery and lowers the cached stock so the cashier
  /// sees an approximate remaining quantity until the next catalogue refresh.
  Future<void> enqueueSale({
    required String businessId,
    required String userId,
    required String deviceId,
    required Json saleRequest,
    required Money previewTotal,
    required String summary,
  }) async {
    final now = _now();
    final payload = {
      ...saleRequest,
      'device_id': deviceId,
      'client_created_at': saleRequest['client_created_at'] ?? now.toUtc().toIso8601String(),
    };
    final reference = payload['client_reference'] as String;
    await db.transaction(() async {
      // Re-queuing the same sale (double tap, retry) must not lower the cached stock twice.
      final exists = await (db.select(
        db.pendingSales,
      )..where((t) => t.clientReference.equals(reference))).getSingleOrNull();
      if (exists != null) return;
      await db.enqueueSale(
        PendingSalesCompanion.insert(
          clientReference: reference,
          businessId: businessId,
          userId: userId,
          payloadJson: jsonEncode(payload),
          previewTotal: previewTotal.toApi(),
          summary: summary,
          createdAt: now,
        ),
      );
      for (final item in (payload['items'] as List).cast<Json>()) {
        await _decrementCached(businessId, item['product_id'] as String, Quantity.parse(item['quantity'] as String));
      }
    });
  }

  Future<void> _decrementCached(String businessId, String productId, Quantity sold) async {
    final row = await (db.select(
      db.cachedProducts,
    )..where((t) => t.businessId.equals(businessId) & t.id.equals(productId))).getSingleOrNull();
    if (row == null) return;
    final j = jsonDecode(row.json) as Json;
    if (j['track_stock'] != true) return;
    j['quantity_on_hand'] = (Quantity.parse(j['quantity_on_hand'] as String) - sold).toString();
    await db.upsertProduct(row.toCompanion(false).copyWith(json: Value(jsonEncode(j))));
  }

  /// Pushes due sales in batches. Safe to call repeatedly and concurrently with the UI.
  Future<SyncReport> syncSales(String businessId, String userId, String deviceId) async {
    var accepted = 0, duplicates = 0, rejected = 0;
    while (true) {
      final due = await db.dueSales(businessId, userId, _now(), limit: batchSize);
      if (due.isEmpty) break;
      for (final s in due) {
        await db.updateSale(s.clientReference, const PendingSalesCompanion(state: Value('syncing')));
      }
      final Json response;
      try {
        response = await client.post<Json>(
          '/businesses/$businessId/sync/sales',
          data: {'device_id': deviceId, 'sales': due.map((s) => jsonDecode(s.payloadJson)).toList()},
        );
      } on ApiError catch (e) {
        await _deferAll(due, e);
        return SyncReport(accepted: accepted, duplicates: duplicates, rejected: rejected, failed: true, error: e);
      }
      final now = _now();
      for (final r in (response['results'] as List).cast<Json>()) {
        final ref = r['client_reference'] as String;
        switch (r['status']) {
          case 'accepted' || 'duplicate':
            r['status'] == 'accepted' ? accepted++ : duplicates++;
            await db.updateSale(
              ref,
              PendingSalesCompanion(
                state: Value(r['status'] as String),
                serverSaleId: Value(r['sale_id'] as String?),
                receiptNumber: Value(r['receipt_number'] as String?),
                acknowledgedAt: Value(now),
                lastErrorCode: const Value(null),
                lastErrorMessage: const Value(null),
              ),
            );
          default:
            rejected++;
            final err = (r['error'] as Map?)?.cast<String, dynamic>() ?? const {};
            await db.updateSale(
              ref,
              PendingSalesCompanion(
                state: const Value('rejected'),
                lastErrorCode: Value('${err['code'] ?? 'rejected'}'),
                lastErrorMessage: Value('${err['message'] ?? 'The server could not record this sale.'}'),
                acknowledgedAt: Value(now),
              ),
            );
        }
      }
    }
    await db.pruneAcknowledged(_now().subtract(_keepAcknowledged));
    return SyncReport(accepted: accepted, duplicates: duplicates, rejected: rejected);
  }

  Future<void> _deferAll(List<PendingSale> sales, ApiError e) async {
    for (final s in sales) {
      final attempts = s.attempts + 1;
      await db.updateSale(
        s.clientReference,
        PendingSalesCompanion(
          state: const Value('pending'),
          attempts: Value(attempts),
          nextAttemptAt: Value(_now().add(backoff(attempts))),
          lastErrorCode: Value(e.code),
          lastErrorMessage: Value(e.message),
        ),
      );
    }
  }

  /// Make a pending sale eligible immediately (manual "Sync now").
  Future<void> resetBackoff(String businessId) =>
      (db.update(db.pendingSales)..where((t) => t.businessId.equals(businessId) & t.state.equals('pending'))).write(
        const PendingSalesCompanion(nextAttemptAt: Value(null)),
      );
}

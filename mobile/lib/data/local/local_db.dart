import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

/// Last-synced copy of a product, used for offline search and selling.
/// Stock figures here are a snapshot and are always shown as "as of last sync".
class CachedProducts extends Table {
  TextColumn get businessId => text()();
  TextColumn get id => text()();
  TextColumn get nameLower => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  BoolColumn get isActive => boolean()();

  /// Full API JSON so the model can be rebuilt without a second schema.
  TextColumn get json => text()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {businessId, id};
}

/// A sale recorded on this device that the server has not acknowledged yet.
///
/// `clientReference` is the idempotency key sent to the server; it never changes,
/// so resending after a timeout or app restart can never create a duplicate.
class PendingSales extends Table {
  TextColumn get clientReference => text()();
  TextColumn get businessId => text()();

  /// The cashier who recorded it. Only that user's session may send it, so a different
  /// person signing in on a shared phone can never submit sales under their own name.
  TextColumn get userId => text()();
  TextColumn get payloadJson => text()();

  /// Preview figures for the UI only; the server recalculates on sync.
  TextColumn get previewTotal => text()();
  TextColumn get summary => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// pending | syncing | accepted | duplicate | rejected
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  TextColumn get serverSaleId => text().nullable()();
  TextColumn get receiptNumber => text().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {clientReference};
}

/// Small key/value store (cached business profile, last sync times).
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [CachedProducts, PendingSales, KeyValues])
class LocalDb extends _$LocalDb {
  LocalDb([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'bizflow'));

  @override
  int get schemaVersion => 1;

  // --- Key/value -----------------------------------------------------------

  Future<String?> readValue(String key) async =>
      (await (select(keyValues)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeValue(String key, String value) =>
      into(keyValues).insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: value));

  // --- Product cache -------------------------------------------------------

  Future<void> replaceProducts(String businessId, List<CachedProductsCompanion> rows) => transaction(() async {
    await (delete(cachedProducts)..where((t) => t.businessId.equals(businessId))).go();
    await batch((b) => b.insertAll(cachedProducts, rows));
  });

  Future<void> upsertProduct(CachedProductsCompanion row) => into(cachedProducts).insertOnConflictUpdate(row);

  Future<List<CachedProduct>> searchProducts(String businessId, String query, {int limit = 60}) {
    final q = query.trim().toLowerCase();
    final stmt = select(cachedProducts)
      ..where((t) => t.businessId.equals(businessId) & t.isActive.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.nameLower)])
      ..limit(limit);
    if (q.isNotEmpty) {
      stmt.where((t) => t.nameLower.contains(q) | t.sku.lower().contains(q) | t.barcode.equals(query.trim()));
    }
    return stmt.get();
  }

  Future<CachedProduct?> productByCode(String businessId, String code) =>
      (select(cachedProducts)
            ..where((t) => t.businessId.equals(businessId) & (t.barcode.equals(code) | t.sku.equals(code)))
            ..limit(1))
          .getSingleOrNull();

  // --- Pending sales -------------------------------------------------------

  Future<void> enqueueSale(PendingSalesCompanion row) =>
      into(pendingSales).insert(row, mode: InsertMode.insertOrIgnore);

  Future<List<PendingSale>> dueSales(String businessId, String userId, DateTime now, {int limit = 50}) =>
      (select(pendingSales)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.userId.equals(userId) &
                  t.state.isIn(['pending', 'syncing']) &
                  (t.nextAttemptAt.isNull() | t.nextAttemptAt.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
            ..limit(limit))
          .get();

  Stream<List<PendingSale>> watchUnresolved(String businessId) =>
      (select(pendingSales)
            ..where((t) => t.businessId.equals(businessId) & t.state.isIn(['pending', 'syncing', 'rejected']))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
          .watch();

  Future<void> updateSale(String clientReference, PendingSalesCompanion changes) =>
      (update(pendingSales)..where((t) => t.clientReference.equals(clientReference))).write(changes);

  Future<void> discardSale(String clientReference) =>
      (delete(pendingSales)..where((t) => t.clientReference.equals(clientReference))).go();

  /// Acknowledged sales are kept briefly for the sync history, then pruned.
  Future<void> pruneAcknowledged(DateTime olderThan) => (delete(
    pendingSales,
  )..where((t) => t.state.isIn(['accepted', 'duplicate']) & t.acknowledgedAt.isSmallerThanValue(olderThan))).go();
}

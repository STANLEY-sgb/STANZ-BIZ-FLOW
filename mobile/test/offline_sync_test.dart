import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/api/api_client.dart';
import 'package:stanz_bizflow/core/api/token_store.dart';
import 'package:stanz_bizflow/core/money.dart';
import 'package:stanz_bizflow/data/local/local_db.dart';
import 'package:stanz_bizflow/data/local/offline_providers.dart';
import 'package:stanz_bizflow/data/local/sync_service.dart';

import 'api_client_test.dart' show FakeAdapter, json;

Map<String, dynamic> productJson(String id, String name, {String qty = '5', String? barcode}) => {
  'id': id,
  'name': name,
  'description': null,
  'sku': 'SKU-$id',
  'barcode': barcode,
  'unit': 'pcs',
  'category_id': null,
  'cost_price': '100.00',
  'selling_price': '1000.00',
  'track_stock': true,
  'quantity_on_hand': qty,
  'reorder_level': '0',
  'stock_status': 'in_stock',
  'attributes': <String, dynamic>{},
  'is_active': true,
  'version': 1,
  'created_at': '2026-10-01T10:00:00Z',
  'updated_at': '2026-10-01T10:00:00Z',
};

Map<String, dynamic> saleRequest(String ref, {String productId = 'p1', String qty = '1'}) => {
  'client_reference': ref,
  'items': [
    {'product_id': productId, 'quantity': qty, 'expected_unit_price': '1000.00'},
  ],
  'payments': [
    {'method': 'cash', 'amount': '1000.00'},
  ],
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LocalDb db;
  late DateTime now;
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) server;
  late OfflineSync sync;

  setUp(() async {
    db = LocalDb(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 27, 9);
    server = (_) => json(500, {});
    adapter = FakeAdapter((o) => server(o));
    final tokens = MemoryTokenStore();
    await tokens.write(access: 'a', refresh: 'r');
    final client = ApiClient(tokens: tokens, baseUrl: 'http://test')..dio.httpClientAdapter = adapter;
    sync = OfflineSync(db: db, client: client, clock: () => now);
  });

  tearDown(() => db.close());

  Future<void> enqueue(String ref, {String user = 'u1', String qty = '1'}) => sync.enqueueSale(
    businessId: 'b1',
    userId: user,
    deviceId: 'dev-1',
    saleRequest: saleRequest(ref, qty: qty),
    previewTotal: Money.parse('1000'),
    summary: 'Phone',
  );

  test('catalogue refresh pages through the server and supports offline search and scan', () async {
    server = (o) {
      final offset = o.queryParameters['offset'] as int;
      final items = offset == 0
          ? [productJson('p1', 'Tecno Spark 20', barcode: '6901'), productJson('p2', 'Phone case')]
          : offset == 2
          ? [productJson('p3', 'Charger')]
          : <Map<String, dynamic>>[];
      return json(200, {'items': items, 'total': 3, 'limit': 100, 'offset': offset});
    };
    expect(await sync.refreshProducts('b1'), 3);
    expect((await sync.searchCached('b1', 'spark')).single.name, 'Tecno Spark 20');
    expect((await sync.searchCached('b1', 'sku-p2')).single.name, 'Phone case');
    expect((await sync.cachedByCode('b1', '6901'))?.id, 'p1');
    expect(await sync.searchCached('other-business', ''), isEmpty, reason: 'cache is per business');
    expect(await sync.productsSyncedAt('b1'), isNotNull);
  });

  test('queued sale lowers cached stock and the same reference is stored only once', () async {
    server = (o) => json(200, {
      'items': [productJson('p1', 'Tecno Spark 20', qty: '3')],
      'total': 1,
      'limit': 100,
      'offset': 0,
    });
    await sync.refreshProducts('b1');
    await enqueue('ref-0001', qty: '2');
    await enqueue('ref-0001', qty: '2');
    expect(await db.dueSales('b1', 'u1', now), hasLength(1));
    expect((await sync.searchCached('b1', 'tecno')).single.quantityOnHand.toString(), '1');

    final payload = jsonDecode((await db.dueSales('b1', 'u1', now)).single.payloadJson) as Map<String, dynamic>;
    expect(payload['device_id'], 'dev-1');
    expect(payload['client_created_at'], isNotNull);
    expect(payload.containsKey('total'), isFalse, reason: 'the server always recalculates totals');
  });

  test('accepted, duplicate and rejected results are recorded per sale', () async {
    await enqueue('ref-a');
    await enqueue('ref-b');
    await enqueue('ref-c');
    late Map<String, dynamic> sent;
    server = (o) {
      sent = o.data as Map<String, dynamic>;
      return json(200, {
        'server_time': now.toIso8601String(),
        'results': [
          {'client_reference': 'ref-a', 'status': 'accepted', 'sale_id': 's1', 'receipt_number': 'R-000010'},
          {'client_reference': 'ref-b', 'status': 'duplicate', 'sale_id': 's0', 'receipt_number': 'R-000009'},
          {
            'client_reference': 'ref-c',
            'status': 'rejected',
            'error': {'code': 'insufficient_stock', 'message': 'Not enough stock for Phone.'},
          },
        ],
      });
    };
    final report = await sync.syncSales('b1', 'u1', 'dev-1');
    expect((report.accepted, report.duplicates, report.rejected, report.failed), (1, 1, 1, false));
    expect(sent['device_id'], 'dev-1');
    expect((sent['sales'] as List), hasLength(3));

    final unresolved = await db.watchUnresolved('b1').first;
    expect(unresolved.single.clientReference, 'ref-c', reason: 'rejected sales stay visible for review');
    expect(unresolved.single.lastErrorCode, 'insufficient_stock');
    expect(await db.dueSales('b1', 'u1', now), isEmpty, reason: 'rejected sales are never resent automatically');
  });

  test('a rejected sale can be retried after the cause is fixed, keeping its idempotency key', () async {
    await enqueue('ref-r');
    var stockAvailable = false;
    final sentRefs = <String>[];
    server = (o) {
      final sale = ((o.data as Map)['sales'] as List).single as Map;
      sentRefs.add(sale['client_reference'] as String);
      return json(200, {
        'results': [
          stockAvailable
              ? {'client_reference': 'ref-r', 'status': 'accepted', 'sale_id': 's9', 'receipt_number': 'R-000009'}
              : {
                  'client_reference': 'ref-r',
                  'status': 'rejected',
                  'error': {'code': 'insufficient_stock', 'message': 'Not enough stock.'},
                },
        ],
      });
    };
    expect((await sync.syncSales('b1', 'u1', 'dev-1')).rejected, 1);
    expect(await db.dueSales('b1', 'u1', now), isEmpty);

    stockAvailable = true; // e.g. a manager received stock
    await sync.retryRejected('ref-r');
    final report = await sync.syncSales('b1', 'u1', 'dev-1');
    expect(report.accepted, 1);
    expect(sentRefs, ['ref-r', 'ref-r'], reason: 'the retry must reuse the original idempotency key');
    expect(await db.watchUnresolved('b1').first, isEmpty);
  });

  test('network failure keeps sales queued with bounded exponential backoff', () async {
    await enqueue('ref-a');
    server = (o) => throw DioException.connectionError(requestOptions: o, reason: 'offline');
    final report = await sync.syncSales('b1', 'u1', 'dev-1');
    expect(report.failed, isTrue);
    expect(report.error?.isNetwork, isTrue);

    final row = (await db.watchUnresolved('b1').first).single;
    expect((row.state, row.attempts), ('pending', 1));
    expect(await db.dueSales('b1', 'u1', now), isEmpty, reason: 'not retried before the backoff expires');
    now = now.add(const Duration(seconds: 6));
    expect(await db.dueSales('b1', 'u1', now), hasLength(1));

    expect(OfflineSync.backoff(1), const Duration(seconds: 5));
    expect(OfflineSync.backoff(3), const Duration(seconds: 20));
    expect(OfflineSync.backoff(30), const Duration(minutes: 10));
  });

  test('a different user on the same phone cannot send someone else\'s queued sales', () async {
    await enqueue('ref-a', user: 'cashier-1');
    var calls = 0;
    server = (o) {
      calls++;
      return json(200, {'results': <Object>[]});
    };
    await sync.syncSales('b1', 'cashier-2', 'dev-1');
    expect(calls, 0);
    expect(await db.dueSales('b1', 'cashier-1', now), hasLength(1));
  });

  test('user id is read from the access token payload', () {
    final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': 'user-123', 'sid': 's'}))).replaceAll('=', '');
    expect(userIdFromJwt('header.$payload.signature'), 'user-123');
    expect(userIdFromJwt('garbage'), isNull);
  });
}

import 'dart:async';

import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/session.dart';
import 'local_db.dart';
import 'sync_service.dart';

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
  ref.onDispose(db.close);
  return db;
});

final offlineSyncProvider = Provider<OfflineSync>(
  (ref) => OfflineSync(db: ref.watch(localDbProvider), client: ref.watch(apiClientProvider)),
);

/// Stable per-installation identifier sent with offline sales (not a hardware ID).
final deviceIdProvider = FutureProvider<String>((ref) async {
  final store = ref.watch(tokenStoreProvider);
  final existing = await store.readValue('device_id');
  if (existing != null) return existing;
  final id = 'dev-${const Uuid().v4()}';
  await store.writeValue('device_id', id);
  return id;
});

/// The signed-in user's id, read from the stored access token so it is known even offline.
/// (Only used to label and filter local data; the server verifies the token itself.)
final currentUserIdProvider = FutureProvider<String?>((ref) async {
  ref.watch(sessionProvider.select((s) => s.status));
  final tokens = await ref.watch(tokenStoreProvider).read();
  if (tokens == null) return null;
  return userIdFromJwt(tokens.access);
});

String? userIdFromJwt(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    return payload['sub'] as String?;
  } on FormatException {
    return null;
  }
}

final unresolvedSalesProvider = StreamProvider.autoDispose<List<PendingSale>>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(localDbProvider).watchUnresolved(bid);
});

final productsSyncedAtProvider = FutureProvider.autoDispose<DateTime?>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(offlineSyncProvider).productsSyncedAt(bid);
});

class SyncStatus {
  const SyncStatus({this.running = false, this.lastReport, this.lastRunAt});

  final bool running;
  final SyncReport? lastReport;
  final DateTime? lastRunAt;
}

/// Runs sync passes: at start-up, when connectivity returns, every minute while
/// work is pending, and on demand.
class SyncController extends Notifier<SyncStatus> {
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _timer?.cancel();
      _connectivity?.cancel();
    });
    return const SyncStatus();
  }

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => run());
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) unawaited(run(refreshCatalog: true));
      });
    } on Object {
      // Connectivity plugin unavailable (e.g. tests): the periodic timer still runs.
    }
    unawaited(run(refreshCatalog: true));
  }

  Future<SyncReport?> run({bool refreshCatalog = false, bool manual = false}) async {
    if (state.running) return state.lastReport;
    final bid = ref.read(sessionProvider).activeBusinessId;
    if (bid == null) return null;
    state = SyncStatus(running: true, lastReport: state.lastReport, lastRunAt: state.lastRunAt);
    final sync = ref.read(offlineSyncProvider);
    SyncReport? report;
    try {
      final device = await ref.read(deviceIdProvider.future);
      final userId = await ref.read(currentUserIdProvider.future);
      if (userId == null) return null;
      if (manual) await sync.resetBackoff(bid);
      report = await sync.syncSales(bid, userId, device);
      if (refreshCatalog && !report.failed) {
        await sync.refreshProducts(bid);
        ref.invalidate(productsSyncedAtProvider);
      }
    } on Object {
      report = const SyncReport(failed: true);
    } finally {
      state = SyncStatus(running: false, lastReport: report, lastRunAt: DateTime.now());
    }
    return report;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

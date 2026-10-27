import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bizflow_api.dart';
import '../data/models.dart';
import 'api/api_client.dart';
import 'api/api_error.dart';
import 'api/token_store.dart';
import '../data/local/offline_providers.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(tokens: ref.watch(tokenStoreProvider)));

final apiProvider = Provider<BizFlowApi>((ref) => BizFlowApi(ref.watch(apiClientProvider)));

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState({required this.status, this.user, this.businesses = const [], this.activeBusinessId});

  const SessionState.unknown() : this(status: SessionStatus.unknown);
  const SessionState.signedOut() : this(status: SessionStatus.signedOut);

  final SessionStatus status;
  final User? user;
  final List<MembershipSummary> businesses;
  final String? activeBusinessId;

  MembershipSummary? get activeMembership => businesses.where((b) => b.businessId == activeBusinessId).firstOrNull;

  SessionState copyWith({List<MembershipSummary>? businesses, String? activeBusinessId, User? user}) => SessionState(
    status: status,
    user: user ?? this.user,
    businesses: businesses ?? this.businesses,
    activeBusinessId: activeBusinessId ?? this.activeBusinessId,
  );
}

class SessionController extends Notifier<SessionState> {
  static const _activeKey = 'active_business';

  BizFlowApi get _api => ref.read(apiProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  Timer? _profileRetry;
  int _profileAttempts = 0;

  @override
  SessionState build() {
    ref.onDispose(() => _profileRetry?.cancel());
    ref.read(apiClientProvider).onSessionExpired = () => state = const SessionState.signedOut();
    Future.microtask(bootstrap);
    return const SessionState.unknown();
  }

  Future<void> bootstrap() async {
    if (await _tokens.read() == null) {
      state = const SessionState.signedOut();
      return;
    }
    try {
      await _loadProfile();
    } on ApiError catch (e) {
      if (e.isUnauthorized) {
        await _tokens.clear();
        state = const SessionState.signedOut();
      } else {
        // Offline at launch: keep the user signed in with what we can; screens show offline states.
        state = SessionState(status: SessionStatus.signedIn, activeBusinessId: await _tokens.readValue(_activeKey));
        _scheduleProfileRetry();
      }
    }
  }

  /// After an offline start, keep trying to load the profile (name, memberships) until the
  /// connection is back: 5 s, 10 s, 20 s … capped at 2 minutes.
  void _scheduleProfileRetry() {
    _profileRetry?.cancel();
    final delay = Duration(seconds: (5 * (1 << _profileAttempts.clamp(0, 5))).clamp(5, 120));
    _profileRetry = Timer(delay, () async {
      if (state.status != SessionStatus.signedIn || state.user != null) return;
      _profileAttempts++;
      try {
        await _loadProfile();
        _profileAttempts = 0;
      } on ApiError catch (e) {
        if (e.isUnauthorized) {
          await _tokens.clear();
          state = const SessionState.signedOut();
        } else {
          _scheduleProfileRetry();
        }
      }
    });
  }

  Future<void> _loadProfile() async {
    final me = await _api.me();
    var active = await _tokens.readValue(_activeKey);
    if (!me.businesses.any((b) => b.businessId == active)) {
      active = me.businesses.length == 1 ? me.businesses.first.businessId : null;
      await _tokens.writeValue(_activeKey, active);
    }
    state = SessionState(
      status: SessionStatus.signedIn,
      user: me.user,
      businesses: me.businesses,
      activeBusinessId: active,
    );
  }

  Future<void> _storeTokens(Json res) =>
      _tokens.write(access: res['access_token'] as String, refresh: res['refresh_token'] as String);

  Future<void> login(String email, String password) async {
    await _storeTokens(await _api.login(email.trim(), password));
    await _loadProfile();
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    await _storeTokens(
      await _api.register(fullName: fullName.trim(), email: email.trim(), password: password, phone: phone),
    );
    await _loadProfile();
  }

  Future<void> refreshProfile() => _loadProfile();

  Future<void> selectBusiness(String id) async {
    await _tokens.writeValue(_activeKey, id);
    state = state.copyWith(activeBusinessId: id);
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on ApiError {
      // Signing out locally must succeed even when offline.
    }
    await _tokens.clear();
    await _tokens.writeValue(_activeKey, null);
    state = const SessionState.signedOut();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Full details (role, permissions, settings) of the active business.
///
/// The last good copy is cached on the device so selling keeps working offline;
/// the server still re-checks every permission when queued sales sync.
final currentBusinessProvider = FutureProvider<Business>((ref) async {
  final id = ref.watch(sessionProvider.select((s) => s.activeBusinessId));
  if (id == null) throw const ApiError(code: 'no_business', message: 'No business selected.');
  final offline = ref.watch(offlineSyncProvider);
  try {
    final json = await ref.watch(apiClientProvider).get<Json>('/businesses/$id');
    await offline.cacheBusiness(json);
    return Business.fromJson(json);
  } on ApiError catch (e) {
    if (!e.isNetwork) rethrow;
    final cached = await offline.cachedBusiness(id);
    if (cached == null) rethrow;
    return cached;
  }
});

/// Synchronous access to the active business id for feature providers.
final activeBusinessIdProvider = Provider<String>((ref) {
  final id = ref.watch(sessionProvider.select((s) => s.activeBusinessId));
  if (id == null) throw StateError('No active business');
  return id;
});

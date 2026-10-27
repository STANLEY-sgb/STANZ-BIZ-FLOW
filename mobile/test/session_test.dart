import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/api/api_client.dart';
import 'package:stanz_bizflow/core/api/token_store.dart';
import 'package:stanz_bizflow/core/session.dart';

import 'api_client_test.dart' show FakeAdapter, json;

void main() {
  test('after an offline start the profile is loaded once the server is reachable (found on device)', () {
    fakeAsync((async) {
      final tokens = MemoryTokenStore();
      tokens.write(access: 'a', refresh: 'r');
      tokens.writeValue('active_business', 'b1');
      var online = false;
      final adapter = FakeAdapter((o) {
        if (!online) throw DioException.connectionError(requestOptions: o, reason: 'offline');
        return json(200, {
          'user': {'id': 'u1', 'email': 'a@example.com', 'full_name': 'Stanley Musinguzi', 'phone': null},
          'businesses': [
            {'business_id': 'b1', 'business_name': 'Stanz Phone World', 'role': 'owner', 'onboarding_completed': true},
          ],
        });
      });
      final client = ApiClient(tokens: tokens, baseUrl: 'http://test')..dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(tokens), apiClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      container.read(sessionProvider);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 50));
      var s = container.read(sessionProvider);
      expect(s.status, SessionStatus.signedIn, reason: 'offline start keeps the user signed in');
      expect(s.user, isNull);
      expect(s.activeBusinessId, 'b1');

      online = true;
      async.elapse(const Duration(seconds: 6));
      s = container.read(sessionProvider);
      expect(s.user?.firstName, 'Stanley');
      expect(s.businesses.single.businessName, 'Stanz Phone World');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/app/router.dart';
import 'package:stanz_bizflow/core/session.dart';
import 'package:stanz_bizflow/data/models.dart';

void main() {
  const user = User(id: 'u1', email: 'a@example.com', fullName: 'Amina Nakato');
  MembershipSummary m(String id, {bool done = true, String role = 'owner'}) =>
      MembershipSummary(businessId: id, businessName: 'Shop $id', role: role, onboardingCompleted: done);
  SessionState signedIn(List<MembershipSummary> b, {String? active}) =>
      SessionState(status: SessionStatus.signedIn, user: user, businesses: b, activeBusinessId: active);

  test('unknown session shows splash', () {
    expect(redirectFor(const SessionState.unknown(), '/home'), '/splash');
    expect(redirectFor(const SessionState.unknown(), '/splash'), isNull);
  });

  test('signed-out users only reach public screens', () {
    const s = SessionState.signedOut();
    expect(redirectFor(s, '/home'), '/welcome');
    expect(redirectFor(s, '/products/123'), '/welcome');
    expect(redirectFor(s, '/login'), isNull);
    expect(redirectFor(s, '/register'), isNull);
  });

  test('new users without a business go to onboarding', () {
    final s = signedIn([]);
    expect(redirectFor(s, '/home'), '/onboarding');
    expect(redirectFor(s, '/login'), '/home');
    expect(redirectFor(s, '/onboarding'), isNull);
    expect(redirectFor(s, '/invite'), isNull);
  });

  test('multi-business users must pick a business', () {
    final s = signedIn([m('a'), m('b')]);
    expect(redirectFor(s, '/home'), '/select-business');
    expect(redirectFor(signedIn([m('a'), m('b')], active: 'b'), '/home'), isNull);
  });

  test('owners with unfinished onboarding resume the checklist', () {
    final s = signedIn([m('a', done: false)], active: 'a');
    expect(redirectFor(s, '/home'), '/setup');
    expect(redirectFor(s, '/products/new'), isNull, reason: 'checklist links must stay reachable');
    final cashier = signedIn([m('a', done: false, role: 'cashier')], active: 'a');
    expect(redirectFor(cashier, '/home'), isNull, reason: 'staff are never blocked by owner setup');
  });
}

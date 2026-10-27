import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/money.dart';
import 'package:stanz_bizflow/features/pos/cart.dart';

import 'test_helpers.dart';

void main() {
  late ProviderContainer container;
  CartController cart() => container.read(cartProvider.notifier);
  Cart state() => container.read(cartProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('adding the same product merges lines and totals are exact', () {
    final phone = testProduct();
    final caseItem = testProduct(id: 'p2', name: 'Case', price: '15000');
    cart().add(phone);
    cart().add(caseItem);
    cart().add(caseItem);
    expect(state().lines, hasLength(2));
    expect(state().quantityOf('p2').toString(), '2');
    expect(state().itemCount.toString(), '3');
    expect(state().subtotal, Money.parse('680000'));
  });

  test('discount reduces total but never below zero', () {
    cart().add(testProduct(price: '1000'));
    cart().setDiscount(Money.parse('200'));
    expect(state().total, Money.parse('800'));
    cart().setDiscount(Money.parse('5000'));
    expect(state().total, Money.zero);
    cart().setDiscount(null);
    expect(state().total, Money.parse('1000'));
  });

  test('decrementing to zero removes the line', () {
    cart().add(testProduct());
    cart().decrement('p1');
    expect(state().isEmpty, isTrue);
  });

  test('checkout reference is stable across retries and reset when the cart changes', () {
    cart().add(testProduct());
    final first = cart().beginCheckout();
    expect(cart().beginCheckout(), first, reason: 'a retry must reuse the idempotency key');
    cart().increment('p1');
    expect(state().checkoutReference, isNull);
    expect(cart().beginCheckout(), isNot(first));
  });

  test('sale request sends quantities and expected prices, never totals', () {
    cart().add(testProduct());
    cart().beginCheckout();
    final body = state().toSaleRequest(payments: [(method: 'cash', amount: Money.parse('700000'), reference: null)]);
    expect(body['client_reference'], isNotNull);
    expect(body.containsKey('total'), isFalse);
    expect(body['items'], [
      {'product_id': 'p1', 'quantity': '1', 'expected_unit_price': '650000.00'},
    ]);
    expect(body['payments'], [
      {'method': 'cash', 'amount': '700000.00'},
    ]);
  });
}

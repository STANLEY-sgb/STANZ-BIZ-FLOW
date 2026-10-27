import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../../data/models.dart';

class CartLine {
  const CartLine({required this.product, required this.quantity});

  final Product product;
  final Quantity quantity;

  Money get total => product.sellingPrice.times(quantity);

  CartLine withQuantity(Quantity q) => CartLine(product: product, quantity: q);
}

/// Cart state. Totals here are a preview; the server recalculates authoritatively.
class Cart {
  const Cart({this.lines = const [], this.orderDiscount, this.checkoutReference});

  final List<CartLine> lines;
  final Money? orderDiscount;

  /// Idempotency key for the current checkout. Reused across retries of the
  /// same sale so a timeout never produces a duplicate; reset after success.
  final String? checkoutReference;

  bool get isEmpty => lines.isEmpty;

  Quantity get itemCount => lines.fold(Quantity.whole(0), (sum, l) => sum + l.quantity);

  Money get subtotal => lines.fold(Money.zero, (sum, l) => sum + l.total);

  Money get discount => orderDiscount ?? Money.zero;

  Money get total {
    final t = subtotal - discount;
    return t.isNegative ? Money.zero : t;
  }

  Quantity quantityOf(String productId) =>
      lines.where((l) => l.product.id == productId).firstOrNull?.quantity ?? Quantity.whole(0);

  Cart copyWith({
    List<CartLine>? lines,
    Money? orderDiscount,
    bool clearDiscount = false,
    String? checkoutReference,
    bool clearReference = false,
  }) => Cart(
    lines: lines ?? this.lines,
    orderDiscount: clearDiscount ? null : (orderDiscount ?? this.orderDiscount),
    checkoutReference: clearReference ? null : (checkoutReference ?? this.checkoutReference),
  );

  /// Request body for POST /sales.
  Map<String, Object?> toSaleRequest({
    required List<({String method, Money amount, String? reference})> payments,
    String? customerId,
  }) => {
    'client_reference': checkoutReference,
    'items': [
      for (final l in lines)
        {
          'product_id': l.product.id,
          'quantity': l.quantity.toString(),
          // Lets the server reject the sale if the price changed since the cashier saw it.
          'expected_unit_price': l.product.sellingPrice.toApi(),
        },
    ],
    if (orderDiscount != null && !orderDiscount!.isZero) 'order_discount': orderDiscount!.toApi(),
    'payments': [
      for (final p in payments)
        {'method': p.method, 'amount': p.amount.toApi(), if (p.reference != null) 'reference': p.reference},
    ],
    'customer_id': ?customerId,
  };
}

class CartController extends Notifier<Cart> {
  static const _uuid = Uuid();

  @override
  Cart build() => const Cart();

  /// Any change to the cart contents means a different sale, so it needs a new idempotency key.
  void _set(Cart next) => state = next.copyWith(clearReference: true);

  void add(Product product, {Quantity? quantity}) {
    final q = quantity ?? Quantity.whole(1);
    final i = state.lines.indexWhere((l) => l.product.id == product.id);
    final lines = [...state.lines];
    if (i >= 0) {
      lines[i] = lines[i].withQuantity(lines[i].quantity + q);
    } else {
      lines.add(CartLine(product: product, quantity: q));
    }
    _set(state.copyWith(lines: lines));
  }

  void setQuantity(String productId, Quantity q) {
    final lines = [
      for (final l in state.lines)
        if (l.product.id != productId) l else if (q.isPositive) l.withQuantity(q),
    ];
    _set(state.copyWith(lines: lines));
  }

  void increment(String productId) => setQuantity(productId, state.quantityOf(productId) + Quantity.whole(1));

  void decrement(String productId) => setQuantity(productId, state.quantityOf(productId) - Quantity.whole(1));

  void remove(String productId) => setQuantity(productId, Quantity.whole(0));

  void setDiscount(Money? discount) => _set(
    discount == null || discount.isZero ? state.copyWith(clearDiscount: true) : state.copyWith(orderDiscount: discount),
  );

  /// Returns the idempotency key for this checkout, creating it on first use.
  String beginCheckout() {
    final ref = state.checkoutReference ?? _uuid.v4().replaceAll('-', '');
    state = state.copyWith(checkoutReference: ref);
    return ref;
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

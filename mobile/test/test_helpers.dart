import 'package:stanz_bizflow/core/money.dart';
import 'package:stanz_bizflow/data/models.dart';

Product testProduct({
  String id = 'p1',
  String name = 'Samsung Galaxy A15',
  String price = '650000',
  String qty = '5',
  bool trackStock = true,
  Map<String, dynamic> attributes = const {'brand': 'Samsung', 'storage': '128GB'},
}) => Product(
  id: id,
  name: name,
  sellingPrice: Money.parse(price),
  costPrice: Money.parse('500000'),
  quantityOnHand: Quantity.parse(qty),
  reorderLevel: Quantity.whole(2),
  stockStatus: StockStatus.inStock,
  trackStock: trackStock,
  unit: 'pcs',
  version: 1,
  isActive: true,
  updatedAt: DateTime(2026, 10, 1),
  attributes: attributes,
);

Business testBusiness({Set<String>? permissions, String role = 'owner'}) => Business(
  id: 'b1',
  name: 'Kampala Phones',
  category: 'electronics',
  countryCode: 'UG',
  currency: 'UGX',
  timezone: 'Africa/Kampala',
  paymentMethods: const ['cash', 'mobile_money'],
  enforceStock: true,
  onboardingStep: 'done',
  onboardingCompleted: true,
  role: role,
  permissions:
      permissions ??
      {
        Perm.salesCreate,
        Perm.salesDiscount,
        Perm.productsManage,
        Perm.productsViewCost,
        Perm.reportsView,
        Perm.expensesManage,
        Perm.inventoryAdjust,
        Perm.inventoryView,
      },
);

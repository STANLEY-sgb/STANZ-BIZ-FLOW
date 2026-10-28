import '../core/api/api_client.dart' show fileUrl;
import '../core/money.dart';

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
Money _money(Object? v) => Money.parse(v as String);
Money? _moneyOrNull(Object? v) => v == null ? null : Money.parse(v as String);
Quantity _qty(Object? v) => Quantity.parse(v as String);

class User {
  const User({required this.id, required this.email, required this.fullName, this.phone});

  final String id;
  final String email;
  final String fullName;
  final String? phone;

  String get firstName => fullName.split(' ').first;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String,
    email: j['email'] as String,
    fullName: j['full_name'] as String,
    phone: j['phone'] as String?,
  );
}

class MembershipSummary {
  const MembershipSummary({
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.onboardingCompleted,
  });

  final String businessId;
  final String businessName;
  final String role;
  final bool onboardingCompleted;

  factory MembershipSummary.fromJson(Map<String, dynamic> j) => MembershipSummary(
    businessId: j['business_id'] as String,
    businessName: j['business_name'] as String,
    role: j['role'] as String,
    onboardingCompleted: j['onboarding_completed'] as bool,
  );
}

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.category,
    required this.countryCode,
    required this.currency,
    required this.timezone,
    required this.paymentMethods,
    required this.enforceStock,
    required this.onboardingStep,
    required this.onboardingCompleted,
    required this.role,
    required this.permissions,
    this.phone,
    this.address,
    this.receiptFooter,
    this.taxRatePercent = '0',
    this.logoUrl,
  });

  final String id;
  final String name;
  final String category;
  final String countryCode;
  final String currency;
  final String timezone;
  final List<String> paymentMethods;
  final bool enforceStock;
  final String onboardingStep;
  final bool onboardingCompleted;
  final String role;
  final Set<String> permissions;
  final String? phone;
  final String? address;
  final String? receiptFooter;
  final String taxRatePercent;
  final String? logoUrl;

  /// UI hint only; the server enforces every permission.
  bool can(String permission) => permissions.contains(permission);

  factory Business.fromJson(Map<String, dynamic> j) => Business(
    id: j['id'] as String,
    name: j['name'] as String,
    category: j['category'] as String,
    countryCode: j['country_code'] as String,
    currency: j['currency'] as String,
    timezone: j['timezone'] as String,
    paymentMethods: (j['payment_methods'] as List).cast<String>(),
    enforceStock: j['enforce_stock'] as bool,
    onboardingStep: j['onboarding_step'] as String,
    onboardingCompleted: j['onboarding_completed'] as bool,
    role: j['role'] as String,
    permissions: (j['permissions'] as List).cast<String>().toSet(),
    phone: j['phone'] as String?,
    address: j['address'] as String?,
    receiptFooter: j['receipt_footer'] as String?,
    taxRatePercent: '${j['tax_rate_percent']}',
    logoUrl: fileUrl(j['logo_url'] as String?),
  );
}

abstract final class Perm {
  static const businessManage = 'business.manage';
  static const teamView = 'team.view';
  static const teamManage = 'team.manage';
  static const subscriptionManage = 'subscription.manage';
  static const productsManage = 'products.manage';
  static const productsViewCost = 'products.view_cost';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryView = 'inventory.view';
  static const salesCreate = 'sales.create';
  static const salesViewAll = 'sales.view_all';
  static const salesDiscount = 'sales.discount';
  static const salesRefund = 'sales.refund';
  static const customersView = 'customers.view';
  static const expensesView = 'expenses.view';
  static const expensesManage = 'expenses.manage';
  static const reportsView = 'reports.view';
}

class Category {
  const Category({required this.id, required this.name, this.productCount = 0});

  final String id;
  final String name;
  final int productCount;

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(id: j['id'] as String, name: j['name'] as String, productCount: (j['product_count'] as int?) ?? 0);
}

enum StockStatus {
  inStock('in_stock', 'In stock'),
  lowStock('low_stock', 'Low stock'),
  outOfStock('out_of_stock', 'Out of stock'),
  untracked('untracked', 'Not tracked');

  const StockStatus(this.api, this.label);
  final String api;
  final String label;

  static StockStatus parse(String v) => values.firstWhere((s) => s.api == v, orElse: () => untracked);
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sellingPrice,
    required this.quantityOnHand,
    required this.reorderLevel,
    required this.stockStatus,
    required this.trackStock,
    required this.unit,
    required this.version,
    required this.isActive,
    required this.updatedAt,
    this.costPrice,
    this.sku,
    this.barcode,
    this.categoryId,
    this.description,
    this.attributes = const {},
    this.imageUrl,
  });

  final String id;
  final String name;
  final Money sellingPrice;
  final Money? costPrice; // null when the role may not see costs
  final Quantity quantityOnHand;
  final Quantity reorderLevel;
  final StockStatus stockStatus;
  final bool trackStock;
  final String unit;
  final int version;
  final bool isActive;
  final DateTime updatedAt;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? description;
  final Map<String, dynamic> attributes;

  /// Absolute, signed and expiring link to the product photo, or null.
  final String? imageUrl;

  String? get brand => attributes['brand'] as String?;

  /// A compact descriptor such as "Samsung · 128GB · Black".
  String get variantLine => [
    attributes['brand'],
    attributes['storage'],
    attributes['colour'],
    attributes['condition'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'] as String,
    name: j['name'] as String,
    sellingPrice: _money(j['selling_price']),
    costPrice: _moneyOrNull(j['cost_price']),
    quantityOnHand: _qty(j['quantity_on_hand']),
    reorderLevel: _qty(j['reorder_level']),
    stockStatus: StockStatus.parse(j['stock_status'] as String),
    trackStock: j['track_stock'] as bool,
    unit: j['unit'] as String,
    version: j['version'] as int,
    isActive: j['is_active'] as bool,
    updatedAt: _date(j['updated_at']),
    sku: j['sku'] as String?,
    barcode: j['barcode'] as String?,
    categoryId: j['category_id'] as String?,
    description: j['description'] as String?,
    attributes: (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
    imageUrl: fileUrl(j['image_url'] as String?),
  );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.reason,
    required this.change,
    required this.after,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String reason;
  final Quantity change;
  final Quantity after;
  final DateTime createdAt;
  final String? note;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
    id: j['id'] as String,
    reason: j['reason'] as String,
    change: _qty(j['quantity_change']),
    after: _qty(j['quantity_after']),
    createdAt: _date(j['created_at']),
    note: j['note'] as String?,
  );
}

class PageResult<T> {
  const PageResult({required this.items, required this.total, required this.offset});

  final List<T> items;
  final int total;
  final int offset;

  bool get hasMore => offset + items.length < total;

  factory PageResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => PageResult(
    items: (j['items'] as List).cast<Map<String, dynamic>>().map(item).toList(),
    total: j['total'] as int,
    offset: j['offset'] as int,
  );
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
    required this.quantityReturned,
  });

  final String id;
  final String productName;
  final Quantity quantity;
  final Money unitPrice;
  final Money discount;
  final Money lineTotal;
  final Quantity quantityReturned;

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
    id: j['id'] as String,
    productName: (j['product_name'] ?? j['name']) as String,
    quantity: _qty(j['quantity']),
    unitPrice: _money(j['unit_price']),
    discount: _money(j['discount']),
    lineTotal: _money(j['line_total']),
    quantityReturned: j['quantity_returned'] == null ? Quantity.whole(0) : _qty(j['quantity_returned']),
  );
}

class SalePayment {
  const SalePayment({required this.kind, required this.method, required this.amount, this.reference});

  final String kind;
  final String method;
  final Money amount;
  final String? reference;

  factory SalePayment.fromJson(Map<String, dynamic> j) => SalePayment(
    kind: j['kind'] as String,
    method: j['method'] as String,
    amount: _money(j['amount']),
    reference: j['reference'] as String?,
  );
}

class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.receiptNumber,
    required this.status,
    required this.total,
    required this.refundedTotal,
    required this.createdAt,
    required this.source,
  });

  final String id;
  final String receiptNumber;
  final String status;
  final Money total;
  final Money refundedTotal;
  final DateTime createdAt;
  final String source;

  factory SaleSummary.fromJson(Map<String, dynamic> j) => SaleSummary(
    id: j['id'] as String,
    receiptNumber: j['receipt_number'] as String,
    status: j['status'] as String,
    total: _money(j['total']),
    refundedTotal: _money(j['refunded_total']),
    createdAt: _date(j['created_at']),
    source: j['source'] as String,
  );
}

class Receipt {
  const Receipt({
    required this.businessName,
    required this.currency,
    required this.receiptNumber,
    required this.issuedAt,
    required this.cashierName,
    required this.lines,
    required this.subtotal,
    required this.discountTotal,
    required this.taxRatePercent,
    required this.taxTotal,
    required this.total,
    required this.amountPaid,
    required this.changeDue,
    required this.refundedTotal,
    required this.payments,
    required this.status,
    this.businessPhone,
    this.businessAddress,
    this.customerName,
    this.footer,
    this.logoUrl,
  });

  final String businessName;
  final String currency;
  final String receiptNumber;
  final DateTime issuedAt;
  final String cashierName;
  final List<SaleLine> lines;
  final Money subtotal;
  final Money discountTotal;
  final String taxRatePercent;
  final Money taxTotal;
  final Money total;
  final Money amountPaid;
  final Money changeDue;
  final Money refundedTotal;
  final List<SalePayment> payments;
  final String status;
  final String? businessPhone;
  final String? businessAddress;
  final String? customerName;
  final String? footer;
  final String? logoUrl;

  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
    businessName: j['business_name'] as String,
    currency: j['currency'] as String,
    receiptNumber: j['receipt_number'] as String,
    issuedAt: _date(j['issued_at']),
    cashierName: j['cashier_name'] as String,
    lines: (j['lines'] as List).cast<Map<String, dynamic>>().map((l) => SaleLine.fromJson({'id': '', ...l})).toList(),
    subtotal: _money(j['subtotal']),
    discountTotal: _money(j['discount_total']),
    taxRatePercent: j['tax_rate_percent'] as String,
    taxTotal: _money(j['tax_total']),
    total: _money(j['total']),
    amountPaid: _money(j['amount_paid']),
    changeDue: _money(j['change_due']),
    refundedTotal: _money(j['refunded_total']),
    payments: (j['payments'] as List).cast<Map<String, dynamic>>().map(SalePayment.fromJson).toList(),
    status: j['status'] as String,
    businessPhone: j['business_phone'] as String?,
    businessAddress: j['business_address'] as String?,
    customerName: j['customer_name'] as String?,
    footer: j['footer'] as String?,
    logoUrl: fileUrl(j['logo_url'] as String?),
  );
}

class ReportSummary {
  const ReportSummary({
    required this.salesCount,
    required this.grossSales,
    required this.discounts,
    required this.refunds,
    required this.netSales,
    required this.averageSale,
    required this.cogs,
    required this.grossProfit,
    required this.costDataComplete,
    required this.expenses,
    required this.netProfit,
  });

  final int salesCount;
  final Money grossSales;
  final Money discounts;
  final Money refunds;
  final Money netSales;
  final Money averageSale;
  final Money cogs;
  final Money grossProfit;
  final bool costDataComplete;
  final Money expenses;
  final Money netProfit;

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    salesCount: j['sales_count'] as int,
    grossSales: _money(j['gross_sales']),
    discounts: _money(j['discounts']),
    refunds: _money(j['refunds']),
    netSales: _money(j['net_sales']),
    averageSale: _money(j['average_sale']),
    cogs: _money(j['cogs']),
    grossProfit: _money(j['gross_profit']),
    costDataComplete: j['cost_data_complete'] as bool,
    expenses: _money(j['expenses']),
    netProfit: _money(j['net_profit']),
  );
}

class DashboardData {
  const DashboardData({
    required this.fullScope,
    required this.currency,
    required this.current,
    required this.previous,
    required this.mySalesCount,
    required this.mySalesAmount,
    required this.activeProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.valuationAtCost,
    required this.lowStock,
    required this.topProducts,
    required this.recentSales,
  });

  final bool fullScope;
  final String currency;
  final ReportSummary? current;
  final ReportSummary? previous;
  final int mySalesCount;
  final Money mySalesAmount;
  final int activeProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final Money? valuationAtCost;
  final List<({String id, String name, Quantity onHand})> lowStock;
  final List<({String name, Quantity quantity, Money revenue})> topProducts;
  final List<({String id, String receiptNumber, Money total, String status, DateTime createdAt})> recentSales;

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final inv = j['inventory'] as Map<String, dynamic>;
    final mine = j['my_sales_today'] as Map<String, dynamic>;
    return DashboardData(
      fullScope: j['scope'] == 'business',
      currency: j['currency'] as String,
      current: j['current'] == null ? null : ReportSummary.fromJson(j['current'] as Map<String, dynamic>),
      previous: j['previous'] == null ? null : ReportSummary.fromJson(j['previous'] as Map<String, dynamic>),
      mySalesCount: mine['count'] as int,
      mySalesAmount: _money(mine['amount']),
      activeProducts: inv['active_products'] as int,
      lowStockCount: inv['low_stock'] as int,
      outOfStockCount: inv['out_of_stock'] as int,
      valuationAtCost: _moneyOrNull(inv['valuation_at_cost']),
      lowStock: [
        for (final r in (j['low_stock'] as List).cast<Map<String, dynamic>>())
          (id: r['product_id'] as String, name: r['name'] as String, onHand: _qty(r['quantity_on_hand'])),
      ],
      topProducts: [
        for (final r in (j['top_products'] as List).cast<Map<String, dynamic>>())
          (name: r['name'] as String, quantity: _qty(r['quantity']), revenue: _money(r['revenue'])),
      ],
      recentSales: [
        for (final r in (j['recent_sales'] as List).cast<Map<String, dynamic>>())
          (
            id: r['id'] as String,
            receiptNumber: r['receipt_number'] as String,
            total: _money(r['total']),
            status: r['status'] as String,
            createdAt: _date(r['created_at']),
          ),
      ],
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.description,
    this.paymentMethod,
    this.supplier,
  });

  final String id;
  final String category;
  final Money amount;
  final DateTime date;
  final String? description;
  final String? paymentMethod;
  final String? supplier;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    category: j['category'] as String,
    amount: _money(j['amount']),
    date: DateTime.parse(j['expense_date'] as String),
    description: j['description'] as String?,
    paymentMethod: j['payment_method'] as String?,
    supplier: j['supplier'] as String?,
  );
}

class Member {
  const Member({required this.membershipId, required this.fullName, required this.email, required this.role});

  final String membershipId;
  final String fullName;
  final String email;
  final String role;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    membershipId: j['membership_id'] as String,
    fullName: j['full_name'] as String,
    email: j['email'] as String,
    role: j['role'] as String,
  );
}

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.usage,
    required this.limits,
    this.trialEndsAt,
  });

  final String planCode;
  final String planName;
  final String status;
  final Map<String, int> usage;
  final Map<String, int?> limits;
  final DateTime? trialEndsAt;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] as Map<String, dynamic>;
    return SubscriptionInfo(
      planCode: plan['code'] as String,
      planName: plan['name'] as String,
      status: j['status'] as String,
      usage: (j['usage'] as Map).cast<String, int>(),
      limits: {
        'products': plan['max_products'] as int?,
        'members': plan['max_members'] as int?,
        'sales_this_month': plan['max_sales_per_month'] as int?,
      },
      trialEndsAt: j['trial_ends_at'] == null ? null : _date(j['trial_ends_at']),
    );
  }
}

String humanize(String code) {
  final s = code.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class ImportIssue {
  const ImportIssue({required this.row, required this.column, required this.message});

  final int row;
  final String column;
  final String message;

  factory ImportIssue.fromJson(Map<String, dynamic> j) =>
      ImportIssue(row: int.parse('${j['row']}'), column: j['column'] as String, message: j['message'] as String);
}

class ImportPreviewRow {
  const ImportPreviewRow({required this.row, required this.action, this.name, this.price, this.quantity, this.message});

  final int row;
  final String action; // create | update | skip | error
  final String? name;
  final Money? price;
  final String? quantity;
  final String? message;

  factory ImportPreviewRow.fromJson(Map<String, dynamic> j) => ImportPreviewRow(
    row: j['row'] as int,
    action: j['action'] as String,
    name: j['name'] as String?,
    price: _moneyOrNull(j['selling_price']),
    quantity: j['quantity'] as String?,
    message: j['message'] as String?,
  );
}

class ImportReport {
  const ImportReport({
    required this.dryRun,
    required this.totalRows,
    required this.toCreate,
    required this.toUpdate,
    required this.skipped,
    required this.invalid,
    required this.errors,
    required this.preview,
    required this.created,
    required this.updated,
    required this.planLimitExceeded,
  });

  final bool dryRun;
  final int totalRows;
  final int toCreate;
  final int toUpdate;
  final int skipped;
  final int invalid;
  final List<ImportIssue> errors;
  final List<ImportPreviewRow> preview;
  final int created;
  final int updated;
  final bool planLimitExceeded;

  int get importable => toCreate + toUpdate;

  factory ImportReport.fromJson(Map<String, dynamic> j) => ImportReport(
    dryRun: j['dry_run'] as bool,
    totalRows: j['total_rows'] as int,
    toCreate: j['to_create'] as int,
    toUpdate: j['to_update'] as int,
    skipped: j['skipped'] as int,
    invalid: j['invalid'] as int,
    errors: (j['errors'] as List).cast<Map<String, dynamic>>().map(ImportIssue.fromJson).toList(),
    preview: (j['preview'] as List).cast<Map<String, dynamic>>().map(ImportPreviewRow.fromJson).toList(),
    created: j['created'] as int,
    updated: j['updated'] as int,
    planLimitExceeded: j['plan_limit_exceeded'] as bool,
  );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.notes,
    this.salesCount,
    this.totalSpent,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;

  /// Only present on the detail endpoint.
  final int? salesCount;
  final Money? totalSpent;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    notes: j['notes'] as String?,
    salesCount: j['sales_count'] as int?,
    totalSpent: _moneyOrNull(j['total_spent']),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/api/api_client.dart';
import 'package:stanz_bizflow/core/api/token_store.dart';
import 'package:stanz_bizflow/core/money.dart';
import 'package:stanz_bizflow/core/session.dart';
import 'package:stanz_bizflow/core/theme/app_theme.dart';
import 'package:stanz_bizflow/core/widgets/widgets.dart';
import 'package:stanz_bizflow/data/bizflow_api.dart';
import 'package:stanz_bizflow/data/models.dart';
import 'package:stanz_bizflow/features/auth/auth_screens.dart';
import 'package:stanz_bizflow/features/dashboard/dashboard_screen.dart';
import 'package:stanz_bizflow/features/products/product_widgets.dart';

import 'test_helpers.dart';

class FakeApi extends BizFlowApi {
  FakeApi(this.data) : super(ApiClient(tokens: MemoryTokenStore(), baseUrl: 'http://test'));

  final DashboardData data;

  @override
  Future<DashboardData> dashboard(String bid, String period) async => data;
}

ReportSummary summary(String net, {bool complete = true}) => ReportSummary(
  salesCount: 4,
  grossSales: Money.parse(net),
  discounts: Money.zero,
  refunds: Money.zero,
  netSales: Money.parse(net),
  averageSale: Money.parse('100000'),
  cogs: Money.parse('200000'),
  grossProfit: Money.parse('200000'),
  costDataComplete: complete,
  expenses: Money.parse('50000'),
  netProfit: Money.parse('150000'),
);

DashboardData dashboardData({bool full = true}) => DashboardData(
  fullScope: full,
  currency: 'UGX',
  current: full ? summary('400000', complete: false) : null,
  previous: full ? summary('200000') : null,
  mySalesCount: 2,
  mySalesAmount: Money.parse('80000'),
  activeProducts: 12,
  lowStockCount: 1,
  outOfStockCount: 0,
  valuationAtCost: full ? Money.parse('9500000') : null,
  lowStock: [(id: 'p1', name: 'Tecno Spark 20 Pro+ 256GB Midnight Black', onHand: Quantity.whole(1))],
  topProducts: [(name: 'Phone case', quantity: Quantity.whole(9), revenue: Money.parse('135000'))],
  recentSales: [
    (
      id: 's1',
      receiptNumber: 'R-000004',
      total: Money.parse('650000'),
      status: 'completed',
      createdAt: DateTime(2026, 10, 27, 14),
    ),
  ],
);

Widget harness(Widget child, {List<Override> overrides = const []}) => ProviderScope(
  overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore()), ...overrides],
  child: MaterialApp(theme: AppTheme.light(), home: child),
);

Future<void> setSurface(WidgetTester tester, Size size, {double textScale = 1}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

List<Override> dashboardOverrides(DashboardData d, {Business? business}) => [
  apiProvider.overrideWithValue(FakeApi(d)),
  activeBusinessIdProvider.overrideWithValue('b1'),
  currentBusinessProvider.overrideWith((ref) async => business ?? testBusiness()),
];

void main() {
  testWidgets('login validates input before calling the server', (tester) async {
    await tester.pumpWidget(harness(const LoginScreen()));
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('password visibility toggle is labelled for screen readers', (tester) async {
    await tester.pumpWidget(harness(const LoginScreen()));
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('owner dashboard shows real figures, comparison and data-quality warning', (tester) async {
    await tester.pumpWidget(harness(const DashboardScreen(), overrides: dashboardOverrides(dashboardData())));
    await tester.pumpAndSettle();
    expect(find.text('UGX 400,000'), findsOneWidget);
    expect(find.text('+100%'), findsOneWidget);
    expect(find.text('Estimate — some items have no cost price'), findsOneWidget);
    expect(find.text('R-000004'), findsOneWidget);
    expect(find.text('New sale'), findsOneWidget);
  });

  testWidgets('cashier dashboard hides business-wide financials', (tester) async {
    final cashier = testBusiness(role: 'cashier', permissions: {Perm.salesCreate});
    await tester.pumpWidget(
      harness(const DashboardScreen(), overrides: dashboardOverrides(dashboardData(full: false), business: cashier)),
    );
    await tester.pumpAndSettle();
    expect(find.text('My sales today'), findsOneWidget);
    expect(find.text('Gross profit'), findsNothing);
    expect(find.text('Add product'), findsNothing);
  });

  for (final (name, size, scale) in [
    ('small phone', const Size(320, 640), 1.0),
    ('small phone, large text', const Size(360, 720), 1.6),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('dashboard has no overflow on $name', (tester) async {
      await setSurface(tester, size, textScale: scale);
      await tester.pumpWidget(harness(const DashboardScreen(), overrides: dashboardOverrides(dashboardData())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('product tile fits a narrow screen with a long name', (tester) async {
    await setSurface(tester, const Size(320, 640), textScale: 1.3);
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProductTile(
              product: testProduct(name: 'Samsung Galaxy A55 5G Dual SIM 256GB Awesome Iceblue Edition'),
              currency: 'UGX',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('UGX 650,000'), findsOneWidget);
  });

  testWidgets('POS tile never truncates the price (found on a Samsung S21 at large font)', (tester) async {
    await setSurface(tester, const Size(360, 780), textScale: 1.6);
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProductTile(
              product: testProduct(price: '1250000'),
              currency: 'UGX',
              trailing: const SizedBox.square(dimension: 36, child: Text('2')),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // The full string is rendered (scaled if needed), never "UGX 1,25…".
    final price = tester.widget<Text>(find.text('UGX 1,250,000'));
    expect(price.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('empty state exposes its action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No products yet',
            message: 'Add items',
            actionLabel: 'Add your first product',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add your first product'));
    expect(tapped, isTrue);
  });

  testWidgets('primary button disables itself while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: PrimaryButton(label: 'Complete sale', loading: true, onPressed: () => taps++),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0, reason: 'double taps during submission must not send twice');
  });
}

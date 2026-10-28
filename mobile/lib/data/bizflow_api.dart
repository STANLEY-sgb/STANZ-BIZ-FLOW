import '../core/api/api_client.dart';
import 'models.dart';

typedef Json = Map<String, dynamic>;

/// Typed wrapper over the STANZ BizFlow REST API (v1).
class BizFlowApi {
  BizFlowApi(this.client);

  final ApiClient client;

  // --- Auth ---------------------------------------------------------------

  Future<Json> register({required String fullName, required String email, required String password, String? phone}) =>
      client.post<Json>(
        '/auth/register',
        data: {'full_name': fullName, 'email': email, 'password': password, 'phone': ?phone},
        auth: false,
      );

  Future<Json> login(String email, String password) => client.post<Json>(
    '/auth/login',
    data: {'email': email, 'password': password, 'device_name': 'BizFlow mobile'},
    auth: false,
  );

  Future<void> logout() => client.post<Json>('/auth/logout');

  Future<String> requestPasswordReset(String email) async =>
      (await client.post<Json>('/auth/password-reset/request', data: {'email': email}, auth: false))['message']
          as String;

  Future<({User user, List<MembershipSummary> businesses})> me() async {
    final j = await client.get<Json>('/auth/me');
    return (
      user: User.fromJson(j['user'] as Json),
      businesses: (j['businesses'] as List).cast<Json>().map(MembershipSummary.fromJson).toList(),
    );
  }

  // --- Businesses ---------------------------------------------------------

  Future<Business> createBusiness(Json body) async =>
      Business.fromJson(await client.post<Json>('/businesses', data: body));

  Future<Business> business(String id) async => Business.fromJson(await client.get<Json>('/businesses/$id'));

  Future<Business> updateBusiness(String id, Json body) async =>
      Business.fromJson(await client.patch<Json>('/businesses/$id', data: body));

  Future<Business> setOnboardingStep(String id, String step) async =>
      Business.fromJson(await client.post<Json>('/businesses/$id/onboarding', data: {'step': step}));

  Future<List<Member>> members(String bid) async =>
      (await client.get<List<dynamic>>('/businesses/$bid/members')).cast<Json>().map(Member.fromJson).toList();

  Future<Json> invite(String bid, String email, String role) =>
      client.post<Json>('/businesses/$bid/invitations', data: {'email': email, 'role': role});

  Future<Business> acceptInvitation(String token) async =>
      Business.fromJson(await client.post<Json>('/invitations/accept', data: {'token': token}));

  Future<SubscriptionInfo> subscription(String bid) async =>
      SubscriptionInfo.fromJson(await client.get<Json>('/businesses/$bid/subscription'));

  Future<SubscriptionInfo> startTrial(String bid, String plan) async => SubscriptionInfo.fromJson(
    await client.post<Json>('/businesses/$bid/subscription/trial', data: {'plan_code': plan}),
  );

  // --- Catalogue ----------------------------------------------------------

  Future<List<Category>> categories(String bid) async =>
      (await client.get<List<dynamic>>('/businesses/$bid/categories')).cast<Json>().map(Category.fromJson).toList();

  Future<Category> createCategory(String bid, String name) async =>
      Category.fromJson(await client.post<Json>('/businesses/$bid/categories', data: {'name': name}));

  Future<PageResult<Product>> products(
    String bid, {
    String? q,
    String? categoryId,
    String? stock,
    int offset = 0,
    int limit = 30,
  }) async => PageResult.fromJson(
    await client.get<Json>(
      '/businesses/$bid/products',
      query: {'q': q, 'category_id': categoryId, 'stock': stock, 'offset': offset, 'limit': limit},
    ),
    Product.fromJson,
  );

  Future<Product> product(String bid, String id) async =>
      Product.fromJson(await client.get<Json>('/businesses/$bid/products/$id'));

  Future<Product> lookup(String bid, String code) async =>
      Product.fromJson(await client.get<Json>('/businesses/$bid/products/lookup', query: {'code': code}));

  Future<Product> createProduct(String bid, Json body) async =>
      Product.fromJson(await client.post<Json>('/businesses/$bid/products', data: body));

  Future<Product> updateProduct(String bid, String id, Json body) async =>
      Product.fromJson(await client.patch<Json>('/businesses/$bid/products/$id', data: body));

  Future<Product> setArchived(String bid, String id, {required bool archived}) async =>
      Product.fromJson(await client.post<Json>('/businesses/$bid/products/$id/${archived ? 'archive' : 'restore'}'));

  /// Dry run (default) returns a validation report; `dryRun: false` applies it in one transaction.
  Future<ImportReport> importProducts(
    String bid, {
    required String filename,
    required List<int> bytes,
    bool dryRun = true,
    bool updateExisting = false,
    bool skipInvalid = false,
  }) async => ImportReport.fromJson(
    await client.postFile<Json>(
      '/businesses/$bid/products/import',
      field: 'file',
      filename: filename,
      bytes: bytes,
      query: {'dry_run': dryRun, 'update_existing': updateExisting, 'skip_invalid': skipInvalid},
    ),
  );

  Future<Product> uploadProductImage(
    String bid,
    String productId, {
    required List<int> bytes,
    required String filename,
  }) async => Product.fromJson(
    await client.postFile<Json>(
      '/businesses/$bid/products/$productId/image',
      field: 'file',
      filename: filename,
      bytes: bytes,
    ),
  );

  Future<Product> deleteProductImage(String bid, String productId) async =>
      Product.fromJson(await client.deleteJson('/businesses/$bid/products/$productId/image'));

  Future<void> uploadLogo(String bid, {required List<int> bytes, required String filename}) =>
      client.postFile<Json>('/businesses/$bid/logo', field: 'file', filename: filename, bytes: bytes);

  Future<void> deleteLogo(String bid) => client.delete('/businesses/$bid/logo');

  Future<List<int>> exportProductsCsv(String bid) => client.getBytes('/businesses/$bid/products/export.csv');

  Future<StockMovement> adjustStock(String bid, String productId, Json body) async => StockMovement.fromJson(
    await client.post<Json>('/businesses/$bid/products/$productId/stock-movements', data: body),
  );

  Future<PageResult<StockMovement>> movements(String bid, {String? productId, int offset = 0}) async =>
      PageResult.fromJson(
        await client.get<Json>('/businesses/$bid/stock-movements', query: {'product_id': productId, 'offset': offset}),
        StockMovement.fromJson,
      );

  // --- Sales --------------------------------------------------------------

  /// Records a sale. `clientReference` makes retries safe: the server returns the original sale.
  Future<Json> createSale(String bid, Json body) => client.post<Json>('/businesses/$bid/sales', data: body);

  Future<PageResult<SaleSummary>> sales(String bid, {int offset = 0, String? q}) async => PageResult.fromJson(
    await client.get<Json>('/businesses/$bid/sales', query: {'offset': offset, 'q': q}),
    SaleSummary.fromJson,
  );

  Future<Json> sale(String bid, String id) => client.get<Json>('/businesses/$bid/sales/$id');

  Future<Receipt> receipt(String bid, String saleId) async =>
      Receipt.fromJson(await client.get<Json>('/businesses/$bid/sales/$saleId/receipt'));

  Future<Json> returnItems(String bid, String saleId, Json body) =>
      client.post<Json>('/businesses/$bid/sales/$saleId/returns', data: body);

  // --- Customers ----------------------------------------------------------

  Future<PageResult<Customer>> customers(String bid, {String? q, int offset = 0}) async => PageResult.fromJson(
    await client.get<Json>('/businesses/$bid/customers', query: {'q': q, 'offset': offset}),
    Customer.fromJson,
  );

  Future<Customer> customer(String bid, String id) async =>
      Customer.fromJson(await client.get<Json>('/businesses/$bid/customers/$id'));

  Future<Customer> createCustomer(String bid, Json body) async =>
      Customer.fromJson(await client.post<Json>('/businesses/$bid/customers', data: body));

  // --- Reports & expenses ---------------------------------------------------

  Future<DashboardData> dashboard(String bid, String period) async =>
      DashboardData.fromJson(await client.get<Json>('/businesses/$bid/dashboard', query: {'period': period}));

  Future<ReportSummary> summary(String bid, {DateTime? from, DateTime? to}) async => ReportSummary.fromJson(
    await client.get<Json>('/businesses/$bid/reports/summary', query: {'date_from': _d(from), 'date_to': _d(to)}),
  );

  Future<List<Json>> report(String bid, String name, {DateTime? from, DateTime? to}) async =>
      (await client.get<List<dynamic>>(
        '/businesses/$bid/reports/$name',
        query: {'date_from': _d(from), 'date_to': _d(to)},
      )).cast<Json>();

  Future<PageResult<Expense>> expenses(String bid, {int offset = 0}) async => PageResult.fromJson(
    await client.get<Json>('/businesses/$bid/expenses', query: {'offset': offset}),
    Expense.fromJson,
  );

  Future<Expense> createExpense(String bid, Json body) async =>
      Expense.fromJson(await client.post<Json>('/businesses/$bid/expenses', data: body));

  Future<void> deleteExpense(String bid, String id) => client.delete('/businesses/$bid/expenses/$id');

  static String? _d(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

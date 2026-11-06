// Contract test: parses real API responses (captured from the seeded demo business by
// backend/scripts/dump_fixtures.py) with the app's own model parsers, so a server/app
// schema drift fails here instead of as an error screen on a phone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/data/models.dart';

Map<String, dynamic> load(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

List<dynamic> loadList(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as List<dynamic>;

void main() {
  test('auth/me', () {
    final j = load('me');
    expect(User.fromJson(j['user'] as Map<String, dynamic>).email, isNotEmpty);
    expect((j['businesses'] as List).cast<Map<String, dynamic>>().map(MembershipSummary.fromJson), isNotEmpty);
  });
  test('business + subscription + members', () {
    expect(Business.fromJson(load('business')).name, isNotEmpty);
    SubscriptionInfo.fromJson(load('subscription'));
    expect(loadList('members').cast<Map<String, dynamic>>().map(Member.fromJson), isNotEmpty);
  });
  test('catalogue', () {
    expect(loadList('categories').cast<Map<String, dynamic>>().map(Category.fromJson), isNotEmpty);
    expect(PageResult.fromJson(load('products'), Product.fromJson).items, isNotEmpty);
    Product.fromJson(load('product'));
    expect(PageResult.fromJson(load('movements'), StockMovement.fromJson).items, isNotEmpty);
  });
  test('sales', () {
    expect(PageResult.fromJson(load('sales'), SaleSummary.fromJson).items, isNotEmpty);
    Receipt.fromJson(load('receipt'));
  });
  test('customers + expenses', () {
    expect(PageResult.fromJson(load('customers'), Customer.fromJson).items, isNotEmpty);
    Customer.fromJson(load('customer'));
    expect(PageResult.fromJson(load('expenses'), Expense.fromJson).items, isNotEmpty);
  });
  test('dashboard + reports', () {
    DashboardData.fromJson(load('dashboard_today'));
    DashboardData.fromJson(load('dashboard_30d'));
    ReportSummary.fromJson(load('summary'));
  });
}

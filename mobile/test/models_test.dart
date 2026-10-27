import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/money.dart';
import 'package:stanz_bizflow/data/models.dart';

void main() {
  test('import report parses the server dry-run response', () {
    final r = ImportReport.fromJson({
      'dry_run': true,
      'total_rows': 3,
      'to_create': 1,
      'to_update': 1,
      'skipped': 0,
      'invalid': 1,
      'errors': [
        {'row': '4', 'column': 'selling_price', 'message': "'abc' is not a valid amount."},
      ],
      'preview': [
        {
          'row': 2,
          'action': 'create',
          'name': 'Tecno Spark 20',
          'sku': 'TS20',
          'selling_price': '450000.00',
          'quantity': '4',
          'message': null,
        },
        {
          'row': 4,
          'action': 'error',
          'name': 'Bad',
          'sku': null,
          'selling_price': null,
          'quantity': null,
          'message': 'x',
        },
      ],
      'created': 0,
      'updated': 0,
      'plan_limit_exceeded': false,
    });
    expect(r.importable, 2);
    expect(r.errors.single.row, 4);
    expect(r.preview.first.price, Money.parse('450000'));
    expect(r.preview.last.price, isNull);
  });

  test('customer detail parses purchase stats when present', () {
    final c = Customer.fromJson({
      'id': 'c1',
      'name': 'Kato John',
      'phone': '+256700000000',
      'email': null,
      'notes': null,
      'sales_count': 3,
      'total_spent': '1250000.00',
    });
    expect(c.totalSpent?.format('UGX'), 'UGX 1,250,000');
    expect(Customer.fromJson({'id': 'c2', 'name': 'Amina'}).salesCount, isNull);
  });
}

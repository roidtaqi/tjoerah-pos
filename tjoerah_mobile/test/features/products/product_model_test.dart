import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/pos/models/product_model.dart';

void main() {
  test('product parses Laravel numeric and boolean values safely', () {
    final product = ProductModel.fromJson({
      'id': 17,
      'name': 'Kopi Susu',
      'base_price': '28000.00',
      'category_id': 3,
      'track_inventory': 1,
      'is_active': false,
      'sla_minutes': '8',
    });

    expect(product.id, '17');
    expect(product.price, 28000);
    expect(product.categoryId, '3');
    expect(product.trackInventory, isTrue);
    expect(product.isActive, isFalse);
    expect(product.slaMinutes, 8);
  });

  test('product draft trims optional values for API mutations', () {
    const draft = ProductDraft(
      name: '  Americano  ',
      price: 22000,
      sku: '  AME-001 ',
      barcode: ' ',
      station: 'bar',
      isActive: true,
    );

    final json = draft.toJson();
    expect(json['name'], 'Americano');
    expect(json['sku'], 'AME-001');
    expect(json['barcode'], isNull);
    expect(json['base_price'], 22000);
  });
}

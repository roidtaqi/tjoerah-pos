import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/cash/models/cash_model.dart';

void main() {
  test('cash summary separates manual cash fund from cash on hand', () {
    final summary = CashSummary.fromJson({
      'opening_cash': 100000,
      'cash_sales': 35000,
      'manual_cash_in': 10000,
      'cash_refunds': 5000,
      'manual_cash_out': 20000,
      'adjustments_in': 2000,
      'adjustments_out': 1000,
      'cash_fund_balance': 91000,
      'cash_on_hand': 121000,
      'expected_cash': 121000,
    });

    expect(summary.cashFundIn, 12000);
    expect(summary.cashFundOut, 21000);
    expect(summary.cashFundBalance, 91000);
    expect(summary.cashOnHand, 121000);
  });

  test('cash summary derives new totals from a legacy API response', () {
    final summary = CashSummary.fromJson({
      'opening_cash': 100000,
      'cash_sales': 35000,
      'manual_cash_in': 0,
      'cash_refunds': 0,
      'manual_cash_out': 20000,
      'adjustments_in': 0,
      'adjustments_out': 0,
      'expected_cash': 115000,
    });

    expect(summary.cashFundBalance, 80000);
    expect(summary.cashOnHand, 115000);
  });
}

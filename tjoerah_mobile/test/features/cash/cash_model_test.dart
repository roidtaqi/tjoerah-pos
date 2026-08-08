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

  test('cash overview reads shared-session permissions', () {
    final overview = CashOverview.fromJson({
      'outlet': {'id': 2, 'name': 'Tjoerah Renon'},
      'current_shift': {
        'id': 8,
        'outlet_id': 2,
        'shift_number': 'KAS-008',
        'status': 'open',
        'started_at': '2026-08-08T07:30:00+08:00',
        'opened_by': {'name': 'Ayu'},
        'summary': <String, dynamic>{},
        'movements': <dynamic>[],
      },
      'permissions': {
        'can_open': false,
        'can_record_movement': true,
        'can_close': false,
        'can_emergency_close': false,
        'monitor_only': false,
        'joined_shared_shift': true,
      },
      'recent_shifts': <dynamic>[],
    });

    expect(overview.currentShift?.openedBy, 'Ayu');
    expect(overview.canOpen, isFalse);
    expect(overview.canRecordMovement, isTrue);
    expect(overview.canClose, isFalse);
    expect(overview.joinedSharedShift, isTrue);
    expect(overview.monitorOnly, isFalse);
  });
}

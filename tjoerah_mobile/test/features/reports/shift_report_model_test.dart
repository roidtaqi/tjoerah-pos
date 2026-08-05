import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/reports/models/report_models.dart';

void main() {
  test('shift report keeps every standard payment method', () {
    final report = ShiftReportModel.fromJson({
      'date': '2026-08-05',
      'total_orders': 4,
      'gross_revenue': 175000,
      'refund_total': 25000,
      'total_revenue': 150000,
      'payment_breakdown': {'cash': 75000, 'qris': 100000},
      'payment_counts': {'cash': 2, 'qris': 2},
      'refund_breakdown': {'cash': 25000},
    });

    expect(report.paymentBreakdown, {
      'cash': 75000,
      'qris': 100000,
      'debit': 0,
    });
    expect(report.paymentCounts, {'cash': 2, 'qris': 2, 'debit': 0});
    expect(report.grossRevenue, 175000);
    expect(report.refundTotal, 25000);
    expect(report.totalRevenue, 150000);
  });
}

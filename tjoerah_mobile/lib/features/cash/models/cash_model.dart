class CashOverview {
  const CashOverview({
    required this.outletId,
    required this.outletName,
    required this.canAdjust,
    required this.recentShifts,
    this.currentShift,
  });

  final int outletId;
  final String outletName;
  final bool canAdjust;
  final CashShift? currentShift;
  final List<CashShift> recentShifts;

  factory CashOverview.fromJson(Map<String, dynamic> json) {
    final outlet = _map(json['outlet']);
    final current = json['current_shift'];
    return CashOverview(
      outletId: _integer(outlet['id']),
      outletName: outlet['name']?.toString() ?? 'Outlet',
      canAdjust: json['can_adjust'] == true,
      currentShift: current is Map
          ? CashShift.fromJson(Map<String, dynamic>.from(current))
          : null,
      recentShifts: _list(json['recent_shifts'])
          .whereType<Map>()
          .map((item) => CashShift.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class CashShift {
  const CashShift({
    required this.id,
    required this.outletId,
    required this.number,
    required this.status,
    required this.startedAt,
    required this.summary,
    required this.movements,
    this.endedAt,
    this.openedBy,
    this.closedBy,
  });

  final int id;
  final int outletId;
  final String number;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? openedBy;
  final String? closedBy;
  final CashSummary summary;
  final List<CashMovement> movements;

  bool get isOpen => status == 'open';

  factory CashShift.fromJson(Map<String, dynamic> json) {
    return CashShift(
      id: _integer(json['id']),
      outletId: _integer(json['outlet_id']),
      number: json['shift_number']?.toString() ?? '-',
      status: json['status']?.toString() ?? 'closed',
      startedAt:
          DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
      openedBy: _map(json['opened_by'])['name']?.toString(),
      closedBy: _map(json['closed_by'])['name']?.toString(),
      summary: CashSummary.fromJson(_map(json['summary'])),
      movements: _list(json['movements'])
          .whereType<Map>()
          .map((item) => CashMovement.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class CashSummary {
  const CashSummary({
    required this.openingCash,
    required this.cashSales,
    required this.manualCashIn,
    required this.cashRefunds,
    required this.manualCashOut,
    required this.adjustmentsIn,
    required this.adjustmentsOut,
    required this.expectedCash,
    this.closingCash,
    this.difference,
  });

  final double openingCash;
  final double cashSales;
  final double manualCashIn;
  final double cashRefunds;
  final double manualCashOut;
  final double adjustmentsIn;
  final double adjustmentsOut;
  final double expectedCash;
  final double? closingCash;
  final double? difference;

  double get totalIn => openingCash + cashSales + manualCashIn + adjustmentsIn;
  double get totalOut => cashRefunds + manualCashOut + adjustmentsOut;

  factory CashSummary.fromJson(Map<String, dynamic> json) => CashSummary(
    openingCash: _number(json['opening_cash']),
    cashSales: _number(json['cash_sales']),
    manualCashIn: _number(json['manual_cash_in']),
    cashRefunds: _number(json['cash_refunds']),
    manualCashOut: _number(json['manual_cash_out']),
    adjustmentsIn: _number(json['adjustments_in']),
    adjustmentsOut: _number(json['adjustments_out']),
    expectedCash: _number(json['expected_cash']),
    closingCash: json['closing_cash'] == null
        ? null
        : _number(json['closing_cash']),
    difference: json['difference'] == null ? null : _number(json['difference']),
  );
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.type,
    required this.category,
    required this.amount,
    required this.signedAmount,
    required this.occurredAt,
    required this.hasEvidence,
    this.note,
    this.referenceNumber,
    this.userName,
  });

  final int id;
  final String type;
  final String category;
  final double amount;
  final double signedAmount;
  final String? note;
  final String? referenceNumber;
  final DateTime occurredAt;
  final bool hasEvidence;
  final String? userName;

  bool get isOut => signedAmount < 0;

  factory CashMovement.fromJson(Map<String, dynamic> json) => CashMovement(
    id: _integer(json['id']),
    type: json['type']?.toString() ?? 'cash_in',
    category: json['category']?.toString() ?? 'other',
    amount: _number(json['amount']),
    signedAmount: _number(json['signed_amount']),
    note: json['note']?.toString(),
    referenceNumber: json['reference_number']?.toString(),
    occurredAt:
        DateTime.tryParse(json['occurred_at']?.toString() ?? '') ??
        DateTime.now(),
    hasEvidence: json['has_evidence'] == true,
    userName: _map(json['user'])['name']?.toString(),
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<dynamic> _list(Object? value) => value is List ? value : const [];

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

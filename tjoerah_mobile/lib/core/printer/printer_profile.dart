enum PrinterDestination { cashier, kitchen, bar }

extension PrinterDestinationDetails on PrinterDestination {
  String get title => switch (this) {
    PrinterDestination.cashier => 'Printer kasir',
    PrinterDestination.kitchen => 'Printer dapur',
    PrinterDestination.bar => 'Printer bar',
  };

  String get shortLabel => switch (this) {
    PrinterDestination.cashier => 'Kasir',
    PrinterDestination.kitchen => 'Dapur',
    PrinterDestination.bar => 'Bar',
  };

  String get description => switch (this) {
    PrinterDestination.cashier => 'Struk pelanggan dan laporan shift',
    PrinterDestination.kitchen =>
      'Tiket makanan dan stasiun tanpa printer khusus',
    PrinterDestination.bar => 'Tiket minuman dari stasiun bar',
  };
}

enum PrinterPaperWidth { mm58, mm80 }

extension PrinterPaperWidthDetails on PrinterPaperWidth {
  String get label => switch (this) {
    PrinterPaperWidth.mm58 => '58 mm',
    PrinterPaperWidth.mm80 => '80 mm',
  };

  int get characters => switch (this) {
    PrinterPaperWidth.mm58 => 32,
    PrinterPaperWidth.mm80 => 48,
  };
}

class PrinterProfile {
  const PrinterProfile({
    required this.destination,
    required this.paperWidth,
    required this.copies,
    required this.autoPrint,
    required this.cutPaper,
    this.deviceAddress,
    this.deviceName,
  });

  factory PrinterProfile.defaults(PrinterDestination destination) {
    return PrinterProfile(
      destination: destination,
      paperWidth: PrinterPaperWidth.mm58,
      copies: 1,
      autoPrint: true,
      cutPaper: true,
    );
  }

  factory PrinterProfile.fromJson(
    PrinterDestination destination,
    Map<String, dynamic> json,
  ) {
    return PrinterProfile(
      destination: destination,
      deviceAddress: json['device_address']?.toString(),
      deviceName: json['device_name']?.toString(),
      paperWidth: PrinterPaperWidth.values.firstWhere(
        (width) => width.name == json['paper_width'],
        orElse: () => PrinterPaperWidth.mm58,
      ),
      copies: ((json['copies'] as num?)?.toInt() ?? 1).clamp(1, 3),
      autoPrint: json['auto_print'] as bool? ?? true,
      cutPaper: json['cut_paper'] as bool? ?? true,
    );
  }

  final PrinterDestination destination;
  final String? deviceAddress;
  final String? deviceName;
  final PrinterPaperWidth paperWidth;
  final int copies;
  final bool autoPrint;
  final bool cutPaper;

  bool get isConfigured =>
      deviceAddress != null && deviceAddress!.trim().isNotEmpty;

  PrinterProfile copyWith({
    String? deviceAddress,
    String? deviceName,
    PrinterPaperWidth? paperWidth,
    int? copies,
    bool? autoPrint,
    bool? cutPaper,
    bool clearDevice = false,
  }) {
    return PrinterProfile(
      destination: destination,
      deviceAddress: clearDevice ? null : (deviceAddress ?? this.deviceAddress),
      deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
      paperWidth: paperWidth ?? this.paperWidth,
      copies: (copies ?? this.copies).clamp(1, 3),
      autoPrint: autoPrint ?? this.autoPrint,
      cutPaper: cutPaper ?? this.cutPaper,
    );
  }

  Map<String, dynamic> toJson() => {
    'device_address': deviceAddress,
    'device_name': deviceName,
    'paper_width': paperWidth.name,
    'copies': copies,
    'auto_print': autoPrint,
    'cut_paper': cutPaper,
  };
}

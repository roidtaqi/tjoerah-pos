import 'printer_profile.dart';

class PrinterDevice {
  const PrinterDevice({required this.name, required this.identifier});

  final String name;
  final String identifier;

  PrinterDevice normalized() => PrinterDevice(
    name: name.trim().isEmpty ? 'Printer tanpa nama' : name.trim(),
    identifier: normalizePrinterAddress(identifier),
  );
}

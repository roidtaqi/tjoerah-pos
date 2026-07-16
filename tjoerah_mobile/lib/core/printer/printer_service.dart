import 'package:flutter/foundation.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
// Note: ESC/POS utils might be needed for proper formatting (e.g. esc_pos_utils_plus)

class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  Future<List<BluetoothDevice>> getDevices() async {
    try {
      return await _printer.getBondedDevices();
    } catch (e) {
      debugPrint('Failed to get bluetooth devices: $e');
      return [];
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      final isConnected = await _printer.isConnected;
      if (isConnected == true) {
        await _printer.disconnect();
      }
      return await _printer.connect(device) ?? false;
    } catch (e) {
      debugPrint('Failed to connect to printer: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await _printer.disconnect();
  }

  Future<void> printReceipt(Map<String, dynamic> order) async {
    final isConnected = await _printer.isConnected;
    if (isConnected != true) {
      debugPrint('Printer not connected.');
      return;
    }

    // --- ESC/POS Receipt Skeleton ---
    // In the future, use esc_pos_utils_plus to generate bytes
    // Example using basic text printing provided by blue_thermal_printer:

    _printer.printNewLine();
    _printer.printCustom("TJOERAH COFFEE", 2, 1);
    _printer.printNewLine();

    _printer.printCustom("Receipt #: ${order['receipt_number']}", 0, 0);
    _printer.printCustom("Date: ${order['created_at']}", 0, 0);
    _printer.printCustom("Customer: ${order['customer'] ?? 'Guest'}", 0, 0);
    _printer.printCustom("--------------------------------", 0, 1);

    final items = order['items'] as List<dynamic>;
    for (var item in items) {
      final name = item['name'] as String;
      final qty = item['qty'] as int;
      final price = item['total'] as double;
      _printer.printCustom("${qty}x $name - Rp$price", 0, 0);
    }

    _printer.printCustom("--------------------------------", 0, 1);
    _printer.printCustom("Total: Rp${order['total']}", 1, 0);
    _printer.printNewLine();
    _printer.printCustom("Thank you for your visit!", 0, 1);
    _printer.printNewLine();
    _printer.printNewLine();
    _printer.paperCut();
  }

  Future<void> printKitchenTicket(Map<String, dynamic> ticket) async {
    final isConnected = await _printer.isConnected;
    if (isConnected != true) {
      debugPrint('Printer not connected.');
      return;
    }

    _printer.printNewLine();
    _printer.printCustom("KITCHEN TICKET", 2, 1);
    _printer.printCustom("Station: ${ticket['station']}", 1, 1);
    _printer.printNewLine();

    _printer.printCustom("Order ID: ${ticket['order_id']}", 0, 0);
    _printer.printCustom("Time: ${ticket['created_at']}", 0, 0);
    _printer.printCustom("--------------------------------", 0, 1);

    final items = ticket['items'] as List<dynamic>;
    for (var item in items) {
      final name = item['name'] as String;
      final qty = item['qty'] as int;
      _printer.printCustom("[ ] ${qty}x $name", 1, 0);

      final notes = item['notes'] as String?;
      if (notes != null && notes.isNotEmpty) {
        _printer.printCustom("    Note: $notes", 0, 0);
      }
    }

    _printer.printNewLine();
    _printer.printNewLine();
    _printer.paperCut();
  }

  Future<void> printShiftReport(Map<String, dynamic> report) async {
    final isConnected = await _printer.isConnected;
    if (isConnected != true) {
      debugPrint('Printer not connected.');
      return;
    }

    _printer.printNewLine();
    _printer.printCustom("END OF DAY REPORT", 2, 1);
    _printer.printCustom("Date: ${report['date']}", 1, 1);
    _printer.printNewLine();

    _printer.printCustom("Total Orders: ${report['total_orders']}", 0, 0);
    _printer.printCustom("Total Revenue: Rp${report['total_revenue']}", 1, 0);
    _printer.printCustom("--------------------------------", 0, 1);
    _printer.printCustom("PAYMENT BREAKDOWN", 1, 1);

    final Map<String, double> breakdown = report['payment_breakdown'] ?? {};
    breakdown.forEach((method, amount) {
      _printer.printCustom("${method.toUpperCase()}: Rp$amount", 0, 0);
    });

    _printer.printCustom("--------------------------------", 0, 1);
    _printer.printNewLine();
    _printer.printCustom(
      "Printed at: ${DateTime.now().toString().split('.')[0]}",
      0,
      1,
    );
    _printer.printNewLine();
    _printer.printNewLine();
    _printer.paperCut();
  }
}

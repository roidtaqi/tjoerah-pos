import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'print_job.dart';

class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  Future<List<BluetoothDevice>> getDevices() async {
    await _prepareBluetooth();
    try {
      return await _printer.getBondedDevices();
    } catch (error) {
      throw PrinterException('Perangkat Bluetooth tidak dapat dibaca: $error');
    }
  }

  Future<void> openBluetoothSettings() async {
    _ensureAndroid();
    try {
      await _printer.openSettings;
    } catch (error) {
      throw PrinterException('Pengaturan Bluetooth tidak dapat dibuka: $error');
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    await _prepareBluetooth();
    if (device.address == null || device.address!.isEmpty) {
      throw const PrinterException('Alamat printer Bluetooth tidak tersedia.');
    }

    try {
      if (await _printer.isDeviceConnected(device) == true) return true;
      if (await _printer.isConnected == true) await _printer.disconnect();

      final result = await _printer.connect(device);
      return result == true || await _printer.isConnected == true;
    } catch (error) {
      throw PrinterException(
        'Tidak dapat terhubung ke ${device.name ?? 'printer'}: $error',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      if (await _printer.isConnected == true) await _printer.disconnect();
    } catch (error) {
      throw PrinterException('Printer tidak dapat diputuskan: $error');
    }
  }

  Future<void> printReceipt(TransactionPrintData order) async {
    await _ensureConnected();
    try {
      await _printer.printNewLine();
      await _printer.printCustom('TJOERAH POS', 2, 1);
      await _printer.printCustom('STRUK PEMBAYARAN', 1, 1);
      await _printer.printNewLine();
      await _printer.printCustom('No: ${order.receiptNumber}', 0, 0);
      await _printer.printCustom('Waktu: ${_dateTime(order.createdAt)}', 0, 0);
      await _printer.printCustom('Pesanan: ${order.orderTypeLabel}', 0, 0);
      if (_hasText(order.tableName)) {
        await _printer.printCustom('Meja: ${order.tableName}', 0, 0);
      }
      if (_hasText(order.customerName)) {
        await _printer.printCustom('Pelanggan: ${order.customerName}', 0, 0);
      }
      await _printer.printCustom(_separator, 0, 1);

      for (final item in order.items) {
        await _printer.printCustom('${item.quantity}x ${item.name}', 0, 0);
        await _printer.printLeftRight(
          '@ ${_money(item.unitPrice)}',
          _money(item.total),
          0,
        );
      }

      await _printer.printCustom(_separator, 0, 1);
      await _printer.printLeftRight('Subtotal', _money(order.subtotal), 0);
      if (order.discount > 0) {
        await _printer.printLeftRight(
          'Diskon',
          '-${_money(order.discount)}',
          0,
        );
      }
      await _printer.printLeftRight('Pajak', _money(order.tax), 0);
      await _printer.printLeftRight('TOTAL', _money(order.total), 1);
      await _printer.printCustom(_separator, 0, 1);
      await _printer.printCustom(
        'Pembayaran: ${order.paymentMethodLabel}',
        0,
        0,
      );
      if (order.paymentMethod == 'split') {
        for (final entry in order.paymentBreakdown.entries) {
          await _printer.printLeftRight(
            _paymentLabel(entry.key),
            _money(entry.value),
            0,
          );
        }
      }
      if (order.amountReceived != null) {
        await _printer.printLeftRight(
          'Diterima',
          _money(order.amountReceived!),
          0,
        );
        await _printer.printLeftRight('Kembali', _money(order.change), 0);
      }
      if (_hasText(order.note)) {
        await _printer.printCustom('Catatan: ${order.note}', 0, 0);
      }
      await _printer.printNewLine();
      await _printer.printCustom('Terima kasih', 0, 1);
      await _finishDocument();
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Struk gagal dicetak: $error');
    }
  }

  Future<void> printKitchenTickets(TransactionPrintData order) async {
    await _ensureConnected();
    try {
      for (final entry in order.itemsByStation.entries) {
        await _printer.printNewLine();
        await _printer.printCustom('PESANAN PRODUKSI', 2, 1);
        await _printer.printCustom(
          productionStationLabel(entry.key).toUpperCase(),
          2,
          1,
        );
        await _printer.printNewLine();
        await _printer.printCustom('No: ${order.receiptNumber}', 1, 0);
        await _printer.printCustom(
          'Waktu: ${_dateTime(order.createdAt)}',
          0,
          0,
        );
        await _printer.printCustom('Tipe: ${order.orderTypeLabel}', 0, 0);
        if (_hasText(order.tableName)) {
          await _printer.printCustom('MEJA: ${order.tableName}', 2, 0);
        }
        if (_hasText(order.customerName)) {
          await _printer.printCustom('Nama: ${order.customerName}', 0, 0);
        }
        await _printer.printCustom(_separator, 0, 1);

        for (final item in entry.value) {
          await _printer.printCustom(
            '[ ] ${item.quantity}x ${item.name}',
            1,
            0,
          );
        }

        if (_hasText(order.note)) {
          await _printer.printCustom(_separator, 0, 1);
          await _printer.printCustom('CATATAN:', 1, 0);
          await _printer.printCustom(order.note!, 1, 0);
        }
        await _finishDocument();
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Tiket dapur gagal dicetak: $error');
    }
  }

  Future<void> printTestPage() async {
    await _ensureConnected();
    try {
      await _printer.printNewLine();
      await _printer.printCustom('TJOERAH POS', 2, 1);
      await _printer.printCustom('PRINTER SIAP', 1, 1);
      await _printer.printCustom(_dateTime(DateTime.now()), 0, 1);
      await _finishDocument();
    } catch (error) {
      throw PrinterException('Cetak tes gagal: $error');
    }
  }

  Future<void> printShiftReport(Map<String, dynamic> report) async {
    await _ensureConnected();
    try {
      await _printer.printNewLine();
      await _printer.printCustom('LAPORAN AKHIR SHIFT', 2, 1);
      await _printer.printCustom('Tanggal: ${report['date']}', 1, 1);
      await _printer.printNewLine();
      await _printer.printCustom(
        'Total pesanan: ${report['total_orders']}',
        0,
        0,
      );
      await _printer.printCustom(
        'Total pendapatan: ${_money(_asDouble(report['total_revenue']))}',
        1,
        0,
      );
      await _printer.printCustom(_separator, 0, 1);
      await _printer.printCustom('RINCIAN PEMBAYARAN', 1, 1);

      final breakdown = report['payment_breakdown'];
      if (breakdown is Map) {
        for (final entry in breakdown.entries) {
          await _printer.printLeftRight(
            _paymentLabel(entry.key.toString()),
            _money(_asDouble(entry.value)),
            0,
          );
        }
      }
      await _finishDocument();
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Laporan shift gagal dicetak: $error');
    }
  }

  Future<void> _prepareBluetooth() async {
    _ensureAndroid();

    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied = statuses.values.where((status) => !status.isGranted);
    if (denied.isNotEmpty) {
      final permanentlyDenied = statuses.values.any(
        (status) => status.isPermanentlyDenied,
      );
      throw PrinterException(
        permanentlyDenied
            ? 'Izin Bluetooth ditolak permanen. Aktifkan dari Pengaturan aplikasi.'
            : 'Izin Bluetooth diperlukan untuk mencari dan memakai printer.',
      );
    }

    if (await _printer.isAvailable != true) {
      throw const PrinterException(
        'Perangkat ini tidak mendukung printer Bluetooth.',
      );
    }
    if (await _printer.isOn != true) {
      throw const PrinterException('Bluetooth belum aktif.');
    }
  }

  void _ensureAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const PrinterException(
        'Printer Bluetooth hanya tersedia pada perangkat Android.',
      );
    }
  }

  Future<void> _ensureConnected() async {
    _ensureAndroid();
    try {
      if (await _printer.isConnected != true) {
        throw const PrinterException(
          'Printer belum terhubung. Pilih printer dari Pengaturan.',
        );
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Status printer tidak dapat dibaca: $error');
    }
  }

  Future<void> _finishDocument() async {
    await _printer.printNewLine();
    await _printer.printNewLine();
    await _printer.printNewLine();
    try {
      await _printer.paperCut();
    } catch (error) {
      debugPrint('Paper cut is not supported by this printer: $error');
    }
  }

  static const _separator = '--------------------------------';

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String _dateTime(DateTime value) =>
      DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

  static String _money(double value) =>
      'Rp${NumberFormat.decimalPattern('id_ID').format(value.round())}';

  static String _paymentLabel(String method) => switch (method) {
    'cash' => 'Tunai',
    'qris' => 'QRIS',
    'card' => 'Kartu',
    _ => method,
  };

  static double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

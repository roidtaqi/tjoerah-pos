import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'print_job.dart';
import 'printer_profile.dart';

class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();
  static const MethodChannel _systemChannel = MethodChannel(
    'com.tjoerah.tjoerah_mobile/system',
  );

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;
  String? _connectedAddress;

  static const Duration _deviceSwitchDelay = Duration(milliseconds: 350);

  Future<List<BluetoothDevice>> getDevices() async {
    await _prepareBluetooth();
    try {
      final bondedDevices = await _printer.getBondedDevices();
      final devicesByAddress = <String, BluetoothDevice>{};
      for (final device in bondedDevices) {
        final address = normalizePrinterAddress(device.address);
        if (address.isEmpty) continue;
        devicesByAddress[address] = BluetoothDevice(device.name, address);
      }
      final devices = devicesByAddress.values.toList()
        ..sort((left, right) {
          final leftName = left.name?.trim().toLowerCase() ?? '';
          final rightName = right.name?.trim().toLowerCase() ?? '';
          final byName = leftName.compareTo(rightName);
          return byName != 0
              ? byName
              : normalizePrinterAddress(
                  left.address,
                ).compareTo(normalizePrinterAddress(right.address));
        });
      return devices;
    } catch (error) {
      throw PrinterException('Perangkat Bluetooth tidak dapat dibaca: $error');
    }
  }

  Future<void> openBluetoothSettings() async {
    _ensureAndroid();
    try {
      final opened = await _systemChannel.invokeMethod<bool>(
        'openBluetoothSettings',
      );
      if (opened != true) {
        throw const PrinterException(
          'Perangkat tidak dapat membuka pengaturan Bluetooth.',
        );
      }
    } catch (error) {
      throw PrinterException('Pengaturan Bluetooth tidak dapat dibuka: $error');
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    await _prepareBluetooth();
    final targetAddress = normalizePrinterAddress(device.address);
    if (targetAddress.isEmpty) {
      throw const PrinterException('Alamat printer Bluetooth tidak tersedia.');
    }

    try {
      final nativeConnected = await _printer.isConnected == true;
      if (canReusePrinterConnection(
        nativeConnected: nativeConnected,
        connectedAddress: _connectedAddress,
        targetAddress: targetAddress,
      )) {
        return;
      }

      if (nativeConnected) {
        await _printer.disconnect();
        _connectedAddress = null;
        await Future<void>.delayed(_deviceSwitchDelay);
      } else {
        _connectedAddress = null;
      }

      await _printer.connect(BluetoothDevice(device.name, targetAddress));
      final connected = await _printer.isConnected == true;
      if (!connected) {
        throw PrinterException(
          'Koneksi ke ${device.name ?? 'printer'} tidak aktif.',
        );
      }
      _connectedAddress = targetAddress;
    } catch (error) {
      _connectedAddress = null;
      if (error is PrinterException) rethrow;
      throw PrinterException(
        'Tidak dapat terhubung ke ${device.name ?? 'printer'}: $error',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      if (await _printer.isConnected == true) {
        await _printer.disconnect();
        await Future<void>.delayed(_deviceSwitchDelay);
      }
    } catch (error) {
      throw PrinterException('Printer tidak dapat diputuskan: $error');
    } finally {
      _connectedAddress = null;
    }
  }

  Future<void> printReceipt(
    TransactionPrintData order, {
    required PrinterPaperWidth paperWidth,
    required bool cutPaper,
  }) async {
    await _ensureConnected();
    final width = paperWidth.characters;
    try {
      await _printer.printNewLine();
      await _printer.printCustom('TJOERAH POS', 2, 1);
      await _printer.printCustom(
        order.isCancelled
            ? 'BUKTI PEMBATALAN'
            : order.isOpenBill
            ? order.isReprint
                  ? 'SALINAN TAGIHAN'
                  : 'TAGIHAN'
            : order.isReprint
            ? 'SALINAN STRUK'
            : 'STRUK PEMBAYARAN',
        1,
        1,
      );
      if (order.isCancelled) {
        await _printer.printCustom('DIBATALKAN', 2, 1);
      } else if (order.isOpenBill) {
        await _printer.printCustom('BELUM LUNAS', 2, 1);
      }
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
      await _printer.printCustom(_separator(width), 0, 1);

      for (final item in order.items) {
        await _printer.printCustom('${item.quantity}x ${item.name}', 0, 0);
        await _printColumns(
          '@ ${_money(item.unitPrice)}',
          _money(item.total),
          width,
        );
      }

      await _printer.printCustom(_separator(width), 0, 1);
      await _printColumns('Subtotal', _money(order.subtotal), width);
      if (order.discount > 0) {
        await _printColumns('Diskon', '-${_money(order.discount)}', width);
      }
      await _printColumns('Pajak', _money(order.tax), width);
      await _printColumns('TOTAL', _money(order.total), width, size: 1);
      await _printer.printCustom(_separator(width), 0, 1);
      if (order.isOpenBill) {
        await _printer.printCustom('Status: BELUM DIBAYAR', 1, 0);
      } else {
        await _printer.printCustom(
          'Pembayaran: ${order.paymentMethodLabel}',
          0,
          0,
        );
        if (order.paymentMethod == 'split') {
          for (final entry in order.paymentBreakdown.entries) {
            await _printColumns(
              _paymentLabel(entry.key),
              _money(entry.value),
              width,
            );
          }
        }
      }
      if (order.amountReceived != null) {
        await _printColumns('Diterima', _money(order.amountReceived!), width);
        await _printColumns('Kembali', _money(order.change), width);
      }
      if (_hasText(order.note)) {
        await _printer.printCustom('Catatan: ${order.note}', 0, 0);
      }
      if (order.isCancelled && _hasText(order.cancellationReason)) {
        await _printer.printCustom(
          'Alasan batal: ${order.cancellationReason}',
          0,
          0,
        );
      }
      await _printer.printNewLine();
      await _printer.printCustom(
        order.isCancelled
            ? 'TRANSAKSI DIBATALKAN'
            : order.isOpenBill
            ? 'Mohon simpan tagihan ini'
            : 'Terima kasih',
        0,
        1,
      );
      await _finishDocument(cutPaper);
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Struk gagal dicetak: $error');
    }
  }

  Future<void> printProductionTicket(
    TransactionPrintData order, {
    required String station,
    required PrinterPaperWidth paperWidth,
    required bool cutPaper,
  }) async {
    if (order.isCancelled) {
      throw PrinterException(
        'Tiket dapur untuk pesanan yang dibatalkan tidak dapat dicetak.',
      );
    }
    await _ensureConnected();
    final items = order.itemsByStation[station] ?? const <PrintOrderItem>[];
    if (items.isEmpty) return;

    final width = paperWidth.characters;
    try {
      await _printer.printNewLine();
      await _printer.printCustom('PESANAN PRODUKSI', 2, 1);
      await _printer.printCustom(
        productionStationLabel(station).toUpperCase(),
        2,
        1,
      );
      if (order.isReprint) {
        await _printer.printCustom('CETAK ULANG', 1, 1);
      }
      await _printer.printNewLine();
      await _printer.printCustom('No: ${order.receiptNumber}', 1, 0);
      await _printer.printCustom('Waktu: ${_dateTime(order.createdAt)}', 0, 0);
      await _printer.printCustom('Tipe: ${order.orderTypeLabel}', 0, 0);
      if (_hasText(order.tableName)) {
        await _printer.printCustom('MEJA: ${order.tableName}', 2, 0);
      }
      if (_hasText(order.customerName)) {
        await _printer.printCustom('Nama: ${order.customerName}', 0, 0);
      }
      await _printer.printCustom(_separator(width), 0, 1);

      for (final item in items) {
        await _printer.printCustom('[ ] ${item.quantity}x ${item.name}', 1, 0);
      }

      if (_hasText(order.note)) {
        await _printer.printCustom(_separator(width), 0, 1);
        await _printer.printCustom('CATATAN:', 1, 0);
        await _printer.printCustom(order.note!, 1, 0);
      }
      await _finishDocument(cutPaper);
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Tiket produksi gagal dicetak: $error');
    }
  }

  Future<void> printTestPage(PrinterProfile profile) async {
    await _ensureConnected();
    try {
      await _printer.printNewLine();
      await _printer.printCustom('TJOERAH POS', 2, 1);
      await _printer.printCustom('PRINTER SIAP', 1, 1);
      await _printer.printCustom(profile.destination.title, 1, 1);
      if (profile.deviceName != null) {
        await _printer.printCustom(profile.deviceName!, 0, 1);
      }
      if (profile.deviceAddress != null) {
        await _printer.printCustom('MAC ${profile.deviceAddress}', 0, 1);
      }
      await _printer.printCustom(
        'Kertas ${profile.paperWidth.label} - ${profile.copies} salinan',
        0,
        1,
      );
      await _printer.printCustom(_dateTime(DateTime.now()), 0, 1);
      await _finishDocument(profile.cutPaper);
    } catch (error) {
      throw PrinterException('Cetak tes gagal: $error');
    }
  }

  Future<void> printShiftReport(
    Map<String, dynamic> report, {
    required PrinterPaperWidth paperWidth,
    required bool cutPaper,
  }) async {
    await _ensureConnected();
    final width = paperWidth.characters;
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
      await _printer.printCustom(_separator(width), 0, 1);
      await _printer.printCustom('RINCIAN PEMBAYARAN', 1, 1);

      final breakdown = report['payment_breakdown'];
      if (breakdown is Map) {
        for (final entry in breakdown.entries) {
          await _printColumns(
            _paymentLabel(entry.key.toString()),
            _money(_asDouble(entry.value)),
            width,
          );
        }
      }
      await _finishDocument(cutPaper);
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
        throw const PrinterException('Printer tujuan belum terhubung.');
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Status printer tidak dapat dibaca: $error');
    }
  }

  Future<void> _printColumns(
    String left,
    String right,
    int width, {
    int size = 0,
  }) async {
    final rightText = right.length >= width ? right.substring(0, width) : right;
    final availableLeft = (width - rightText.length - 1).clamp(1, width);
    final leftText = left.length > availableLeft
        ? left.substring(0, availableLeft)
        : left;
    final spaces = width - leftText.length - rightText.length;
    await _printer.printCustom(
      '$leftText${' ' * spaces.clamp(1, width)}$rightText',
      size,
      0,
    );
  }

  Future<void> _finishDocument(bool cutPaper) async {
    await _printer.printNewLine();
    await _printer.printNewLine();
    await _printer.printNewLine();
    if (!cutPaper) return;
    try {
      await _printer.paperCut();
    } catch (error) {
      debugPrint('Paper cut is not supported by this printer: $error');
    }
  }

  static String _separator(int width) => '-' * width;

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

@visibleForTesting
bool canReusePrinterConnection({
  required bool nativeConnected,
  required String? connectedAddress,
  required String? targetAddress,
}) {
  if (!nativeConnected) return false;
  final connected = normalizePrinterAddress(connectedAddress);
  final target = normalizePrinterAddress(targetAddress);
  return connected.isNotEmpty && connected == target;
}

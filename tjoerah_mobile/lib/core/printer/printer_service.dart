import 'package:blue_thermal_printer/blue_thermal_printer.dart' as classic;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'print_job.dart';
import 'printer_device.dart';
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

  final classic.BlueThermalPrinter _androidPrinter =
      classic.BlueThermalPrinter.instance;
  final Future<CapabilityProfile> _capabilityProfile = CapabilityProfile.load();
  String? _connectedAddress;

  static const Duration _deviceSwitchDelay = Duration(milliseconds: 350);

  Future<List<PrinterDevice>> getDevices() async {
    await _prepareBluetooth();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return _getAndroidDevices();
      }
      return _getIosDevices();
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Perangkat Bluetooth tidak dapat dibaca: $error');
    }
  }

  Future<List<PrinterDevice>> _getAndroidDevices() async {
    final bondedDevices = await _androidPrinter.getBondedDevices();
    return _sortedDevices(
      bondedDevices.map(
        (device) => PrinterDevice(
          name: device.name ?? 'Printer tanpa nama',
          identifier: device.address ?? '',
        ),
      ),
    );
  }

  Future<List<PrinterDevice>> _getIosDevices() async {
    final devicesByAddress = <String, PrinterDevice>{};
    void addDevice(BleDevice device) {
      final address = normalizePrinterAddress(device.deviceId);
      final name = device.name?.trim();
      if (address.isEmpty || name == null || name.isEmpty) return;
      devicesByAddress[address] = PrinterDevice(
        name: name,
        identifier: address,
      );
    }

    final subscription = UniversalBle.scanStream.listen(addDevice);
    try {
      for (final device in await UniversalBle.getSystemDevices()) {
        addDevice(device);
      }
      await UniversalBle.startScan();
      await Future<void>.delayed(const Duration(seconds: 5));
    } finally {
      try {
        await UniversalBle.stopScan();
      } finally {
        await subscription.cancel();
      }
    }
    return _sortedDevices(devicesByAddress.values);
  }

  List<PrinterDevice> _sortedDevices(Iterable<PrinterDevice> source) {
    final devicesByAddress = <String, PrinterDevice>{};
    for (final device in source) {
      final normalized = device.normalized();
      final address = normalized.identifier;
      if (address.isEmpty) continue;
      devicesByAddress[address] = normalized;
    }
    final devices = devicesByAddress.values.toList()
      ..sort((left, right) {
        final byName = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return byName != 0
            ? byName
            : left.identifier.compareTo(right.identifier);
      });
    return devices;
  }

  Future<void> openBluetoothSettings() async {
    _ensureSupportedPlatform();
    try {
      final opened = defaultTargetPlatform == TargetPlatform.iOS
          ? await openAppSettings()
          : await _systemChannel.invokeMethod<bool>('openBluetoothSettings');
      if (opened != true) {
        throw const PrinterException(
          'Perangkat tidak dapat membuka pengaturan Bluetooth.',
        );
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Pengaturan Bluetooth tidak dapat dibuka: $error');
    }
  }

  Future<void> connect(PrinterDevice device) async {
    await _prepareBluetooth();
    final normalizedDevice = device.normalized();
    final targetAddress = normalizedDevice.identifier;
    if (targetAddress.isEmpty) {
      throw const PrinterException('ID printer Bluetooth tidak tersedia.');
    }

    try {
      final nativeConnected = await _nativeConnected(
        fallbackAddress: targetAddress,
      );
      if (canReusePrinterConnection(
        nativeConnected: nativeConnected,
        connectedAddress: _connectedAddress,
        targetAddress: targetAddress,
      )) {
        return;
      }

      if (nativeConnected) {
        await _disconnectNative(targetAddress);
        _connectedAddress = null;
        await Future<void>.delayed(_deviceSwitchDelay);
      } else {
        _connectedAddress = null;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _androidPrinter.connect(
          classic.BluetoothDevice(normalizedDevice.name, targetAddress),
        );
      } else {
        await UniversalBle.connect(
          targetAddress,
          timeout: const Duration(seconds: 20),
        );
      }
      final connected = await _nativeConnected(fallbackAddress: targetAddress);
      if (!connected) {
        throw PrinterException(
          'Koneksi ke ${normalizedDevice.name} tidak aktif.',
        );
      }
      _connectedAddress = targetAddress;
    } catch (error) {
      _connectedAddress = null;
      if (error is PrinterException) rethrow;
      throw PrinterException(
        'Tidak dapat terhubung ke ${normalizedDevice.name}: $error',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      if (await _nativeConnected()) {
        await _disconnectNative(_connectedAddress);
        await Future<void>.delayed(_deviceSwitchDelay);
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
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
    final document = await _newDocument(paperWidth);
    final width = paperWidth.characters;
    try {
      document.newLine();
      document.text('TJOERAH POS', size: 2, align: PosAlign.center);
      document.text(
        order.isCancelled
            ? 'BUKTI PEMBATALAN'
            : order.isOpenBill
            ? order.isReprint
                  ? 'SALINAN TAGIHAN'
                  : 'TAGIHAN'
            : order.isReprint
            ? 'SALINAN STRUK'
            : 'STRUK PEMBAYARAN',
        size: 1,
        align: PosAlign.center,
      );
      if (order.isCancelled) {
        document.text('DIBATALKAN', size: 2, align: PosAlign.center);
      } else if (order.isOpenBill) {
        document.text('BELUM LUNAS', size: 2, align: PosAlign.center);
      }
      document.newLine();
      document.text('No: ${order.receiptNumber}');
      document.text('Waktu: ${_dateTime(order.createdAt)}');
      document.text('Pesanan: ${order.orderTypeLabel}');
      if (_hasText(order.tableName)) {
        document.text('Meja: ${order.tableName}');
      }
      if (_hasText(order.customerName)) {
        document.text('Pelanggan: ${order.customerName}');
      }
      document.text(_separator(width), align: PosAlign.center);

      for (final item in order.items) {
        document.text('${item.quantity}x ${item.name}');
        document.columns(
          '@ ${_money(item.unitPrice)}',
          _money(item.total),
          width,
        );
      }

      document.text(_separator(width), align: PosAlign.center);
      document.columns('Subtotal', _money(order.subtotal), width);
      if (order.discount > 0) {
        document.columns('Diskon', '-${_money(order.discount)}', width);
      }
      document.columns('Pajak', _money(order.tax), width);
      document.columns('TOTAL', _money(order.total), width, size: 1);
      document.text(_separator(width), align: PosAlign.center);
      if (order.isOpenBill) {
        document.text('Status: BELUM DIBAYAR', size: 1);
      } else {
        document.text('Pembayaran: ${order.paymentMethodLabel}');
        if (order.paymentMethod == 'split') {
          for (final entry in order.paymentBreakdown.entries) {
            document.columns(
              _paymentLabel(entry.key),
              _money(entry.value),
              width,
            );
          }
        }
      }
      if (order.amountReceived != null) {
        document.columns('Diterima', _money(order.amountReceived!), width);
        document.columns('Kembali', _money(order.change), width);
      }
      if (_hasText(order.note)) {
        document.text('Catatan: ${order.note}');
      }
      if (order.isCancelled && _hasText(order.cancellationReason)) {
        document.text('Alasan batal: ${order.cancellationReason}');
      }
      document.newLine();
      document.text(
        order.isCancelled
            ? 'TRANSAKSI DIBATALKAN'
            : order.isOpenBill
            ? 'Mohon simpan tagihan ini'
            : 'Terima kasih',
        align: PosAlign.center,
      );
      await _writeDocument(document.finish(cutPaper: cutPaper));
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
      throw const PrinterException(
        'Tiket dapur untuk pesanan yang dibatalkan tidak dapat dicetak.',
      );
    }
    final items = order.itemsByStation[station] ?? const <PrintOrderItem>[];
    if (items.isEmpty) return;

    final document = await _newDocument(paperWidth);
    final width = paperWidth.characters;
    try {
      document.newLine();
      document.text('PESANAN PRODUKSI', size: 2, align: PosAlign.center);
      document.text(
        productionStationLabel(station).toUpperCase(),
        size: 2,
        align: PosAlign.center,
      );
      if (order.isReprint) {
        document.text('CETAK ULANG', size: 1, align: PosAlign.center);
      }
      document.newLine();
      document.text('No: ${order.receiptNumber}', size: 1);
      document.text('Waktu: ${_dateTime(order.createdAt)}');
      document.text('Tipe: ${order.orderTypeLabel}');
      if (_hasText(order.tableName)) {
        document.text('MEJA: ${order.tableName}', size: 2);
      }
      if (_hasText(order.customerName)) {
        document.text('Nama: ${order.customerName}');
      }
      document.text(_separator(width), align: PosAlign.center);

      for (final item in items) {
        document.text('[ ] ${item.quantity}x ${item.name}', size: 1);
      }

      if (_hasText(order.note)) {
        document.text(_separator(width), align: PosAlign.center);
        document.text('CATATAN:', size: 1);
        document.text(order.note!, size: 1);
      }
      await _writeDocument(document.finish(cutPaper: cutPaper));
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Tiket produksi gagal dicetak: $error');
    }
  }

  Future<void> printTestPage(PrinterProfile profile) async {
    final document = await _newDocument(profile.paperWidth);
    try {
      document.newLine();
      document.text('TJOERAH POS', size: 2, align: PosAlign.center);
      document.text('PRINTER SIAP', size: 1, align: PosAlign.center);
      document.text(profile.destination.title, size: 1, align: PosAlign.center);
      if (profile.deviceName != null) {
        document.text(profile.deviceName!, align: PosAlign.center);
      }
      if (profile.deviceAddress != null) {
        document.text('ID ${profile.deviceAddress}', align: PosAlign.center);
      }
      document.text(
        'Kertas ${profile.paperWidth.label} - ${profile.copies} salinan',
        align: PosAlign.center,
      );
      document.text(_dateTime(DateTime.now()), align: PosAlign.center);
      await _writeDocument(document.finish(cutPaper: profile.cutPaper));
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Cetak tes gagal: $error');
    }
  }

  Future<void> printShiftReport(
    Map<String, dynamic> report, {
    required PrinterPaperWidth paperWidth,
    required bool cutPaper,
  }) async {
    final document = await _newDocument(paperWidth);
    final width = paperWidth.characters;
    try {
      document.newLine();
      document.text('LAPORAN AKHIR SHIFT', size: 2, align: PosAlign.center);
      document.text(
        'Tanggal: ${report['date']}',
        size: 1,
        align: PosAlign.center,
      );
      document.text(
        'Dicetak: ${report['generated_at']}',
        align: PosAlign.center,
      );
      document.text('Petugas: ${report['operator']}', align: PosAlign.center);
      document.newLine();
      document.text('Total pesanan: ${report['total_orders']}');
      document.columns(
        'Penjualan kotor',
        _money(_asDouble(report['gross_revenue'])),
        width,
      );
      document.columns(
        'Refund',
        _money(_asDouble(report['refund_total'])),
        width,
      );
      document.columns(
        'Penjualan bersih',
        _money(_asDouble(report['total_revenue'])),
        width,
      );
      document.text(_separator(width), align: PosAlign.center);
      document.text(
        'METODE PEMBAYARAN HARI INI',
        size: 1,
        align: PosAlign.center,
      );

      final breakdown = report['payment_breakdown'];
      final counts = report['payment_counts'];
      var paymentTotal = 0.0;
      if (breakdown is Map) {
        for (final entry in breakdown.entries) {
          final count = counts is Map
              ? _asDouble(counts[entry.key]).toInt()
              : 0;
          final amount = _asDouble(entry.value);
          paymentTotal += amount;
          document.columns(
            '${_paymentLabel(entry.key.toString())} ($count trx)',
            _money(amount),
            width,
          );
        }
      }
      document.columns('TOTAL METODE', _money(paymentTotal), width);

      final cashShift = report['cash_shift'];
      if (cashShift is Map) {
        final cashFundBalance = cashShift['cash_fund_balance'] == null
            ? _asDouble(cashShift['opening_cash']) +
                  _asDouble(cashShift['manual_cash_in']) +
                  _asDouble(cashShift['adjustments_in']) -
                  _asDouble(cashShift['manual_cash_out']) -
                  _asDouble(cashShift['adjustments_out'])
            : _asDouble(cashShift['cash_fund_balance']);
        final cashOnHand = cashShift['cash_on_hand'] == null
            ? cashFundBalance +
                  _asDouble(cashShift['cash_sales']) -
                  _asDouble(cashShift['cash_refunds'])
            : _asDouble(cashShift['cash_on_hand']);
        document.text(_separator(width), align: PosAlign.center);
        document.text(
          'RINCIAN TUNAI DI KASIR',
          size: 1,
          align: PosAlign.center,
        );
        document.text('Sesi: ${cashShift['number']}');
        document.text('Dibuka: ${cashShift['started_at']}');
        document.text('Petugas: ${cashShift['opened_by'] ?? '-'}');
        document.columns(
          'Saldo awal kas',
          _money(_asDouble(cashShift['opening_cash'])),
          width,
        );
        document.columns(
          'Kas masuk manual',
          _money(
            _asDouble(cashShift['manual_cash_in']) +
                _asDouble(cashShift['adjustments_in']),
          ),
          width,
        );
        document.columns(
          'Kas keluar manual',
          _money(
            _asDouble(cashShift['manual_cash_out']) +
                _asDouble(cashShift['adjustments_out']),
          ),
          width,
        );
        document.columns('SALDO UANG KAS', _money(cashFundBalance), width);
        document.columns(
          'Penjualan tunai',
          _money(_asDouble(cashShift['cash_sales'])),
          width,
        );
        document.columns(
          'Refund tunai',
          _money(_asDouble(cashShift['cash_refunds'])),
          width,
        );
        document.columns('TOTAL TUNAI KASIR', _money(cashOnHand), width);
        if (cashShift['closing_cash'] != null) {
          document.columns(
            'Uang fisik',
            _money(_asDouble(cashShift['closing_cash'])),
            width,
          );
          document.columns(
            'SELISIH',
            _money(_asDouble(cashShift['difference'])),
            width,
          );
          document.text('Ditutup: ${cashShift['ended_at']}');
        } else {
          document.text('Status: MASIH BERJALAN', align: PosAlign.center);
        }
      }
      document.text(_separator(width), align: PosAlign.center);
      document.text('Tanda tangan petugas:');
      document.newLine(3);
      document.text('(____________________)', align: PosAlign.center);
      await _writeDocument(document.finish(cutPaper: cutPaper));
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Laporan shift gagal dicetak: $error');
    }
  }

  Future<void> _prepareBluetooth() async {
    _ensureSupportedPlatform();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
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
      if (await _androidPrinter.isAvailable != true) {
        throw const PrinterException(
          'Perangkat ini tidak mendukung printer Bluetooth.',
        );
      }
      if (await _androidPrinter.isOn != true) {
        throw const PrinterException('Bluetooth belum aktif.');
      }
      return;
    }

    try {
      await UniversalBle.requestPermissions();
    } catch (_) {
      throw const PrinterException(
        'Izin Bluetooth diperlukan untuk mencari dan memakai printer.',
      );
    }
    final bluetoothState = await UniversalBle.getBluetoothAvailabilityState();
    switch (bluetoothState) {
      case AvailabilityState.poweredOn:
        return;
      case AvailabilityState.unauthorized:
        throw const PrinterException(
          'Izin Bluetooth ditolak. Aktifkan dari Pengaturan aplikasi.',
        );
      case AvailabilityState.poweredOff:
        throw const PrinterException('Bluetooth belum aktif.');
      case AvailabilityState.unsupported:
        throw const PrinterException(
          'Perangkat ini tidak mendukung printer Bluetooth BLE.',
        );
      case AvailabilityState.unknown:
      case AvailabilityState.resetting:
        throw const PrinterException(
          'Bluetooth belum siap. Tunggu sebentar lalu muat ulang.',
        );
    }
  }

  void _ensureSupportedPlatform() {
    if (kIsWeb || !isPrinterPlatformSupported(defaultTargetPlatform)) {
      throw const PrinterException(
        'Printer Bluetooth tersedia pada perangkat Android dan iOS.',
      );
    }
  }

  Future<_EscPosDocument> _newDocument(PrinterPaperWidth paperWidth) async {
    await _ensureConnected();
    final profile = await _capabilityProfile;
    return _EscPosDocument(
      Generator(
        paperWidth == PrinterPaperWidth.mm58 ? PaperSize.mm58 : PaperSize.mm80,
        profile,
      ),
    );
  }

  Future<void> _ensureConnected() async {
    _ensureSupportedPlatform();
    try {
      if (!await _nativeConnected()) {
        throw const PrinterException('Printer tujuan belum terhubung.');
      }
    } catch (error) {
      if (error is PrinterException) rethrow;
      throw PrinterException('Status printer tidak dapat dibaca: $error');
    }
  }

  Future<void> _writeDocument(List<int> bytes) async {
    if (bytes.isEmpty) {
      throw const PrinterException('Dokumen cetak kosong.');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _androidPrinter.writeBytes(Uint8List.fromList(bytes));
      return;
    }
    await _writeIosDocument(bytes);
  }

  Future<bool> _nativeConnected({String? fallbackAddress}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _androidPrinter.isConnected == true;
    }
    final address = normalizePrinterAddress(
      _connectedAddress ?? fallbackAddress,
    );
    if (address.isEmpty) return false;
    try {
      return await UniversalBle.getConnectionState(address) ==
          BleConnectionState.connected;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disconnectNative(String? fallbackAddress) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _androidPrinter.disconnect();
      return;
    }
    final address = normalizePrinterAddress(
      _connectedAddress ?? fallbackAddress,
    );
    if (address.isNotEmpty) {
      await UniversalBle.disconnect(
        address,
        timeout: const Duration(seconds: 10),
      );
    }
  }

  Future<void> _writeIosDocument(List<int> bytes) async {
    final address = normalizePrinterAddress(_connectedAddress);
    if (address.isEmpty) {
      throw const PrinterException('Printer tujuan belum terhubung.');
    }

    final services = await UniversalBle.discoverServices(
      address,
      timeout: const Duration(seconds: 15),
    );
    _BleWriteTarget? target;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final supportsResponse = characteristic.properties.contains(
          CharacteristicProperty.write,
        );
        final supportsNoResponse = characteristic.properties.contains(
          CharacteristicProperty.writeWithoutResponse,
        );
        if (supportsResponse || supportsNoResponse) {
          target = _BleWriteTarget(
            service: service.uuid,
            characteristic: characteristic.uuid,
            withoutResponse: !supportsResponse,
          );
          if (supportsResponse) break;
        }
      }
      if (target != null && !target.withoutResponse) break;
    }
    if (target == null) {
      throw const PrinterException(
        'Printer BLE tidak menyediakan saluran tulis yang kompatibel.',
      );
    }

    var mtu = 185;
    try {
      mtu = await UniversalBle.requestMtu(
        address,
        185,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {
      // iOS menentukan MTU sendiri; ukuran konservatif tetap aman.
    }
    final chunkSize = (mtu - 3).clamp(20, 150).toInt();
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length).toInt();
      await UniversalBle.write(
        address,
        target.service,
        target.characteristic,
        Uint8List.fromList(bytes.sublist(offset, end)),
        withoutResponse: target.withoutResponse,
        timeout: const Duration(seconds: 10),
      );
      if (target.withoutResponse) {
        await Future<void>.delayed(const Duration(milliseconds: 12));
      }
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
    'card' || 'debit_card' || 'debit' => 'Kartu debit',
    _ => method,
  };

  static double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

class _BleWriteTarget {
  const _BleWriteTarget({
    required this.service,
    required this.characteristic,
    required this.withoutResponse,
  });

  final String service;
  final String characteristic;
  final bool withoutResponse;
}

class _EscPosDocument {
  _EscPosDocument(this._generator) {
    _bytes.addAll(_generator.reset());
  }

  final Generator _generator;
  final List<int> _bytes = [];

  void newLine([int count = 1]) => _bytes.addAll(_generator.emptyLines(count));

  void text(String value, {int size = 0, PosAlign align = PosAlign.left}) {
    final large = size >= 2;
    _bytes.addAll(
      _generator.text(
        value,
        styles: PosStyles(
          bold: size > 0,
          align: align,
          height: large ? PosTextSize.size2 : PosTextSize.size1,
          width: large ? PosTextSize.size2 : PosTextSize.size1,
        ),
      ),
    );
  }

  void columns(String left, String right, int width, {int size = 0}) {
    final rightText = right.length >= width ? right.substring(0, width) : right;
    final availableLeft = (width - rightText.length - 1).clamp(1, width);
    final leftText = left.length > availableLeft
        ? left.substring(0, availableLeft)
        : left;
    final spaces = width - leftText.length - rightText.length;
    text('$leftText${' ' * spaces.clamp(1, width)}$rightText', size: size);
  }

  List<int> finish({required bool cutPaper}) {
    if (cutPaper) {
      _bytes.addAll(_generator.cut());
    } else {
      _bytes.addAll(_generator.feed(3));
    }
    return List<int>.unmodifiable(_bytes);
  }
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

@visibleForTesting
bool isPrinterPlatformSupported(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/printer/print_job.dart';
import '../../../core/printer/printer_service.dart';

class PrinterState {
  const PrinterState({
    this.devices = const [],
    this.connectedDevice,
    this.isScanning = false,
    this.isConnecting = false,
    this.isPrinting = false,
    this.error,
    this.notice,
  });

  final List<BluetoothDevice> devices;
  final BluetoothDevice? connectedDevice;
  final bool isScanning;
  final bool isConnecting;
  final bool isPrinting;
  final String? error;
  final String? notice;

  bool get isReady => connectedDevice != null && !isConnecting;

  PrinterState copyWith({
    List<BluetoothDevice>? devices,
    BluetoothDevice? connectedDevice,
    bool? isScanning,
    bool? isConnecting,
    bool? isPrinting,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
    bool clearConnectedDevice = false,
  }) {
    return PrinterState(
      devices: devices ?? this.devices,
      connectedDevice: clearConnectedDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      isScanning: isScanning ?? this.isScanning,
      isConnecting: isConnecting ?? this.isConnecting,
      isPrinting: isPrinting ?? this.isPrinting,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

class PrinterNotifier extends Notifier<PrinterState> {
  static const _deviceAddressKey = 'printer_device_address';
  static const _deviceNameKey = 'printer_device_name';

  @override
  PrinterState build() {
    Future.microtask(_initialize);
    return const PrinterState();
  }

  Future<void> _initialize() async {
    await scanDevices();
    if (state.devices.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final rememberedAddress = prefs.getString(_deviceAddressKey);
    if (rememberedAddress == null) return;

    final remembered = state.devices.where(
      (device) => device.address == rememberedAddress,
    );
    if (remembered.isNotEmpty) {
      await connect(remembered.first, remember: false);
    }
  }

  Future<void> scanDevices() async {
    state = state.copyWith(
      isScanning: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      final devices = await PrinterService.instance.getDevices();
      state = state.copyWith(devices: devices, isScanning: false);
    } catch (error) {
      state = state.copyWith(
        isScanning: false,
        error: _message(error),
        clearNotice: true,
      );
    }
  }

  Future<void> connect(BluetoothDevice device, {bool remember = true}) async {
    state = state.copyWith(
      isConnecting: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      final success = await PrinterService.instance.connect(device);
      if (!success) {
        throw PrinterException(
          'Tidak dapat terhubung ke ${device.name ?? 'printer'}.',
        );
      }

      if (remember) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_deviceAddressKey, device.address ?? '');
        await prefs.setString(
          _deviceNameKey,
          device.name ?? 'Printer Bluetooth',
        );
      }
      state = state.copyWith(
        connectedDevice: device,
        isConnecting: false,
        notice: '${device.name ?? 'Printer'} siap digunakan.',
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isConnecting: false,
        error: _message(error),
        clearNotice: true,
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await PrinterService.instance.disconnect();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deviceAddressKey);
      await prefs.remove(_deviceNameKey);
      state = state.copyWith(
        clearConnectedDevice: true,
        clearError: true,
        notice: 'Printer diputuskan.',
      );
    } catch (error) {
      state = state.copyWith(error: _message(error), clearNotice: true);
    }
  }

  Future<void> openBluetoothSettings() async {
    try {
      await PrinterService.instance.openBluetoothSettings();
    } catch (error) {
      state = state.copyWith(error: _message(error), clearNotice: true);
    }
  }

  Future<void> testPrint() async {
    if (!state.isReady) {
      state = state.copyWith(
        error: 'Hubungkan printer sebelum mencetak tes.',
        clearNotice: true,
      );
      return;
    }
    try {
      await _runPrint(
        PrinterService.instance.printTestPage,
        successMessage: 'Halaman tes berhasil dicetak.',
      );
    } catch (_) {}
  }

  Future<void> printReceipt(TransactionPrintData order) {
    return _runPrint(
      () => PrinterService.instance.printReceipt(order),
      successMessage: 'Struk berhasil dicetak.',
    );
  }

  Future<void> printKitchenTickets(TransactionPrintData order) {
    return _runPrint(
      () => PrinterService.instance.printKitchenTickets(order),
      successMessage: 'Pesanan dapur berhasil dicetak.',
    );
  }

  Future<void> printTransaction(TransactionPrintData order) {
    return _runPrint(() async {
      await PrinterService.instance.printReceipt(order);
      await PrinterService.instance.printKitchenTickets(order);
    }, successMessage: 'Struk dan pesanan dapur berhasil dicetak.');
  }

  Future<void> _runPrint(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    state = state.copyWith(
      isPrinting: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      await action();
      state = state.copyWith(
        isPrinting: false,
        notice: successMessage,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isPrinting: false,
        error: _message(error),
        clearNotice: true,
      );
      rethrow;
    }
  }

  static String _message(Object error) => error is PrinterException
      ? error.message
      : 'Operasi printer gagal: $error';
}

final printerProvider = NotifierProvider<PrinterNotifier, PrinterState>(
  PrinterNotifier.new,
);

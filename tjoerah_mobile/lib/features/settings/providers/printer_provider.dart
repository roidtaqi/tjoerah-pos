import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import '../../../core/printer/printer_service.dart';

class PrinterState {
  final List<BluetoothDevice> devices;
  final BluetoothDevice? connectedDevice;
  final bool isScanning;
  final bool isConnecting;
  final String? error;

  PrinterState({
    this.devices = const [],
    this.connectedDevice,
    this.isScanning = false,
    this.isConnecting = false,
    this.error,
  });

  PrinterState copyWith({
    List<BluetoothDevice>? devices,
    BluetoothDevice? connectedDevice,
    bool? isScanning,
    bool? isConnecting,
    String? error,
    bool clearError = false,
    bool clearConnectedDevice = false,
  }) {
    return PrinterState(
      devices: devices ?? this.devices,
      connectedDevice: clearConnectedDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      isScanning: isScanning ?? this.isScanning,
      isConnecting: isConnecting ?? this.isConnecting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PrinterNotifier extends Notifier<PrinterState> {
  @override
  PrinterState build() {
    Future.microtask(scanDevices);
    return PrinterState();
  }

  Future<void> scanDevices() async {
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final devices = await PrinterService.instance.getDevices();
      state = state.copyWith(devices: devices, isScanning: false);
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        error: 'Failed to scan devices: $e',
      );
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      final success = await PrinterService.instance.connect(device);
      if (success) {
        state = state.copyWith(connectedDevice: device, isConnecting: false);
      } else {
        state = state.copyWith(
          isConnecting: false,
          error: 'Failed to connect to ${device.name}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await PrinterService.instance.disconnect();
      state = state.copyWith(clearConnectedDevice: true, clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Failed to disconnect: $e');
    }
  }

  Future<void> testPrint() async {
    if (state.connectedDevice == null) return;
    try {
      await PrinterService.instance.printShiftReport({
        'date': 'TEST PRINT',
        'total_orders': 0,
        'total_revenue': 0.0,
        'payment_breakdown': {'test': 0.0},
      });
    } catch (e) {
      state = state.copyWith(error: 'Test print failed: $e');
    }
  }
}

final printerProvider = NotifierProvider<PrinterNotifier, PrinterState>(() {
  return PrinterNotifier();
});

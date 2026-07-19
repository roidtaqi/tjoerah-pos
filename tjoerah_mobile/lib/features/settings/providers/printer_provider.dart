import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/printer/print_job.dart';
import '../../../core/printer/printer_profile.dart';
import '../../../core/printer/printer_service.dart';

class PrinterJobResult {
  const PrinterJobResult({this.completed = const [], this.failures = const []});

  final List<String> completed;
  final List<String> failures;

  bool get isSuccess => failures.isEmpty && completed.isNotEmpty;
  bool get isPartial => failures.isNotEmpty && completed.isNotEmpty;

  String get message {
    if (isSuccess) return '${completed.join(', ')} berhasil dicetak.';
    if (isPartial) {
      return '${completed.join(', ')} berhasil. ${failures.join(' ')}';
    }
    return failures.isEmpty
        ? 'Tidak ada dokumen yang perlu dicetak.'
        : failures.join(' ');
  }
}

class PrinterState {
  PrinterState({
    Map<PrinterDestination, PrinterProfile>? profiles,
    this.devices = const [],
    this.isInitialized = false,
    this.isScanning = false,
    this.activeDestination,
    this.error,
    this.notice,
  }) : profiles = Map.unmodifiable(
         profiles ??
             {
               for (final destination in PrinterDestination.values)
                 destination: PrinterProfile.defaults(destination),
             },
       );

  final Map<PrinterDestination, PrinterProfile> profiles;
  final List<BluetoothDevice> devices;
  final bool isInitialized;
  final bool isScanning;
  final PrinterDestination? activeDestination;
  final String? error;
  final String? notice;

  bool get isPrinting => activeDestination != null;
  bool get hasCashierPrinter =>
      profile(PrinterDestination.cashier).isConfigured;
  bool get hasProductionPrinter =>
      profile(PrinterDestination.kitchen).isConfigured ||
      profile(PrinterDestination.bar).isConfigured;
  bool get hasAnyPrinter =>
      profiles.values.any((profile) => profile.isConfigured);
  bool get hasAutomaticPrinter => profiles.values.any(
    (profile) => profile.isConfigured && profile.autoPrint,
  );

  PrinterProfile profile(PrinterDestination destination) =>
      profiles[destination] ?? PrinterProfile.defaults(destination);

  PrinterState copyWith({
    Map<PrinterDestination, PrinterProfile>? profiles,
    List<BluetoothDevice>? devices,
    bool? isInitialized,
    bool? isScanning,
    PrinterDestination? activeDestination,
    String? error,
    String? notice,
    bool clearActiveDestination = false,
    bool clearError = false,
    bool clearNotice = false,
  }) {
    return PrinterState(
      profiles: profiles ?? this.profiles,
      devices: devices ?? this.devices,
      isInitialized: isInitialized ?? this.isInitialized,
      isScanning: isScanning ?? this.isScanning,
      activeDestination: clearActiveDestination
          ? null
          : (activeDestination ?? this.activeDestination),
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

class PrinterNotifier extends Notifier<PrinterState> {
  static const _profilesKey = 'printer_profiles_v2';
  static const _legacyAddressKey = 'printer_device_address';
  static const _legacyNameKey = 'printer_device_name';

  @override
  PrinterState build() {
    Future.microtask(_loadProfiles);
    return PrinterState();
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    final profiles = <PrinterDestination, PrinterProfile>{};

    if (raw != null) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        for (final destination in PrinterDestination.values) {
          final profileJson = json[destination.name];
          profiles[destination] = profileJson is Map
              ? PrinterProfile.fromJson(
                  destination,
                  Map<String, dynamic>.from(profileJson),
                )
              : PrinterProfile.defaults(destination);
        }
      } catch (_) {
        profiles.clear();
      }
    }

    if (profiles.isEmpty) {
      for (final destination in PrinterDestination.values) {
        profiles[destination] = PrinterProfile.defaults(destination);
      }
      final legacyAddress = prefs.getString(_legacyAddressKey);
      final legacyName = prefs.getString(_legacyNameKey);
      if (legacyAddress != null && legacyAddress.isNotEmpty) {
        for (final destination in [
          PrinterDestination.cashier,
          PrinterDestination.kitchen,
        ]) {
          profiles[destination] = profiles[destination]!.copyWith(
            deviceAddress: legacyAddress,
            deviceName: legacyName ?? 'Printer Bluetooth',
          );
        }
        await _saveProfiles(profiles);
        await prefs.remove(_legacyAddressKey);
        await prefs.remove(_legacyNameKey);
      }
    }

    state = state.copyWith(profiles: profiles, isInitialized: true);
  }

  Future<void> scanDevices() async {
    state = state.copyWith(
      isScanning: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      final devices = await PrinterService.instance.getDevices();
      state = state.copyWith(
        devices: devices,
        isScanning: false,
        notice: devices.isEmpty
            ? 'Belum ada printer yang dipasangkan di Android.'
            : '${devices.length} printer Bluetooth ditemukan.',
      );
    } catch (error) {
      state = state.copyWith(
        isScanning: false,
        error: _message(error),
        clearNotice: true,
      );
    }
  }

  Future<void> assignDevice(
    PrinterDestination destination,
    BluetoothDevice device,
  ) async {
    final profile = state
        .profile(destination)
        .copyWith(
          deviceAddress: device.address,
          deviceName: device.name ?? 'Printer Bluetooth',
        );
    await _updateProfile(
      profile,
      notice: '${profile.destination.title} menggunakan ${profile.deviceName}.',
    );
  }

  Future<void> clearDevice(PrinterDestination destination) async {
    await _updateProfile(
      state.profile(destination).copyWith(clearDevice: true),
      notice: 'Perangkat ${destination.shortLabel.toLowerCase()} dihapus.',
    );
  }

  Future<void> setPaperWidth(
    PrinterDestination destination,
    PrinterPaperWidth width,
  ) => _updateProfile(state.profile(destination).copyWith(paperWidth: width));

  Future<void> setCopies(PrinterDestination destination, int copies) =>
      _updateProfile(state.profile(destination).copyWith(copies: copies));

  Future<void> setAutoPrint(PrinterDestination destination, bool value) =>
      _updateProfile(state.profile(destination).copyWith(autoPrint: value));

  Future<void> setCutPaper(PrinterDestination destination, bool value) =>
      _updateProfile(state.profile(destination).copyWith(cutPaper: value));

  Future<void> openBluetoothSettings() async {
    try {
      await PrinterService.instance.openBluetoothSettings();
    } catch (error) {
      state = state.copyWith(error: _message(error), clearNotice: true);
    }
  }

  Future<PrinterJobResult> testPrint(PrinterDestination destination) async {
    final profile = state.profile(destination);
    if (!profile.isConfigured) {
      return _failed('${destination.title} belum memilih perangkat.');
    }
    return _execute([
      _PrintTask(
        destination: destination,
        label: 'Tes ${destination.shortLabel.toLowerCase()}',
        profile: profile.copyWith(copies: 1),
        print: () => PrinterService.instance.printTestPage(profile),
      ),
    ]);
  }

  Future<PrinterJobResult> printReceipt(TransactionPrintData order) {
    final profile = state.profile(PrinterDestination.cashier);
    if (!profile.isConfigured) {
      return Future.value(_failed('Printer kasir belum diatur.'));
    }
    return _execute([_receiptTask(order, profile)]);
  }

  Future<PrinterJobResult> printKitchenTickets(TransactionPrintData order) {
    final plan = _productionPlan(order, automatic: false);
    return _execute(plan.tasks, initialFailures: plan.failures);
  }

  Future<PrinterJobResult> printTransaction(TransactionPrintData order) {
    final tasks = <_PrintTask>[];
    final failures = <String>[];
    final cashier = state.profile(PrinterDestination.cashier);
    if (cashier.isConfigured) {
      tasks.add(_receiptTask(order, cashier));
    } else {
      failures.add('Printer kasir belum diatur.');
    }
    final production = _productionPlan(order, automatic: false);
    tasks.addAll(production.tasks);
    failures.addAll(production.failures);
    return _execute(tasks, initialFailures: failures);
  }

  Future<PrinterJobResult> autoPrintTransaction(TransactionPrintData order) {
    final tasks = <_PrintTask>[];
    final cashier = state.profile(PrinterDestination.cashier);
    if (cashier.isConfigured && cashier.autoPrint) {
      tasks.add(_receiptTask(order, cashier));
    }
    final production = _productionPlan(order, automatic: true);
    tasks.addAll(production.tasks);
    if (tasks.isEmpty && production.failures.isEmpty) {
      return Future.value(const PrinterJobResult());
    }
    return _execute(tasks, initialFailures: production.failures);
  }

  Future<PrinterJobResult> printShiftReport(Map<String, dynamic> report) {
    final profile = state.profile(PrinterDestination.cashier);
    if (!profile.isConfigured) {
      return Future.value(_failed('Printer kasir belum diatur.'));
    }
    return _execute([
      _PrintTask(
        destination: PrinterDestination.cashier,
        label: 'Laporan shift',
        profile: profile,
        print: () => PrinterService.instance.printShiftReport(
          report,
          paperWidth: profile.paperWidth,
          cutPaper: profile.cutPaper,
        ),
      ),
    ]);
  }

  _PrintTask _receiptTask(TransactionPrintData order, PrinterProfile profile) {
    return _PrintTask(
      destination: PrinterDestination.cashier,
      label: 'Struk pelanggan',
      profile: profile,
      print: () => PrinterService.instance.printReceipt(
        order,
        paperWidth: profile.paperWidth,
        cutPaper: profile.cutPaper,
      ),
    );
  }

  _ProductionPlan _productionPlan(
    TransactionPrintData order, {
    required bool automatic,
  }) {
    final tasks = <_PrintTask>[];
    final failures = <String>[];
    for (final station in order.itemsByStation.keys) {
      final preferred = station == 'bar'
          ? PrinterDestination.bar
          : PrinterDestination.kitchen;
      var profile = state.profile(preferred);
      var destination = preferred;

      if (!profile.isConfigured && preferred == PrinterDestination.bar) {
        destination = PrinterDestination.kitchen;
        profile = state.profile(destination);
      }
      if (!profile.isConfigured) {
        failures.add(
          'Printer untuk tiket ${productionStationLabel(station)} belum diatur.',
        );
        continue;
      }
      if (automatic && !profile.autoPrint) continue;

      tasks.add(
        _PrintTask(
          destination: destination,
          label: 'Tiket ${productionStationLabel(station)}',
          profile: profile,
          print: () => PrinterService.instance.printProductionTicket(
            order,
            station: station,
            paperWidth: profile.paperWidth,
            cutPaper: profile.cutPaper,
          ),
        ),
      );
    }
    return _ProductionPlan(tasks: tasks, failures: failures);
  }

  Future<PrinterJobResult> _execute(
    List<_PrintTask> tasks, {
    List<String> initialFailures = const [],
  }) async {
    if (state.isPrinting) {
      return _failed('Printer sedang menyelesaikan pekerjaan lain.');
    }
    if (tasks.isEmpty && initialFailures.isEmpty) {
      return _failed('Printer produksi belum diatur untuk item pesanan ini.');
    }

    final completed = <String>[];
    final failures = [...initialFailures];
    for (final task in tasks) {
      state = state.copyWith(
        activeDestination: task.destination,
        clearError: true,
        clearNotice: true,
      );
      try {
        await PrinterService.instance.connect(
          BluetoothDevice(task.profile.deviceName, task.profile.deviceAddress),
        );
        for (var copy = 0; copy < task.profile.copies; copy++) {
          await task.print();
        }
        completed.add(task.label);
      } catch (error) {
        failures.add('${task.label} gagal: ${_message(error)}');
      }
    }

    final result = PrinterJobResult(completed: completed, failures: failures);
    state = state.copyWith(
      clearActiveDestination: true,
      error: failures.isEmpty ? null : result.message,
      notice: failures.isEmpty ? result.message : null,
      clearError: failures.isEmpty,
      clearNotice: failures.isNotEmpty,
    );
    return result;
  }

  PrinterJobResult _failed(String message) {
    state = state.copyWith(error: message, clearNotice: true);
    return PrinterJobResult(failures: [message]);
  }

  Future<void> _updateProfile(PrinterProfile profile, {String? notice}) async {
    final profiles = Map<PrinterDestination, PrinterProfile>.from(
      state.profiles,
    )..[profile.destination] = profile;
    await _saveProfiles(profiles);
    state = state.copyWith(
      profiles: profiles,
      notice: notice,
      clearNotice: notice == null,
      clearError: true,
    );
  }

  Future<void> _saveProfiles(
    Map<PrinterDestination, PrinterProfile> profiles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode({
        for (final entry in profiles.entries)
          entry.key.name: entry.value.toJson(),
      }),
    );
  }

  static String _message(Object error) => error is PrinterException
      ? error.message
      : 'Operasi printer gagal: $error';
}

class _PrintTask {
  const _PrintTask({
    required this.destination,
    required this.label,
    required this.profile,
    required this.print,
  });

  final PrinterDestination destination;
  final String label;
  final PrinterProfile profile;
  final Future<void> Function() print;
}

class _ProductionPlan {
  const _ProductionPlan({required this.tasks, required this.failures});

  final List<_PrintTask> tasks;
  final List<String> failures;
}

final printerProvider = NotifierProvider<PrinterNotifier, PrinterState>(
  PrinterNotifier.new,
);

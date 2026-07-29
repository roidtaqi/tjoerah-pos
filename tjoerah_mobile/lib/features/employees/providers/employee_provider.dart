import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/employee_models.dart';

class EmployeeManagementState {
  const EmployeeManagementState({
    required this.employees,
    required this.roles,
    required this.outlets,
    required this.employmentStatuses,
  });

  final List<EmployeeProfile> employees;
  final List<EmployeeRoleOption> roles;
  final List<EmployeeOutletOption> outlets;
  final List<EmploymentStatusOption> employmentStatuses;
}

class EmployeeMutationResult {
  const EmployeeMutationResult(this.isSuccess, this.message);

  final bool isSuccess;
  final String message;
}

class EmployeeNotifier extends AsyncNotifier<EmployeeManagementState> {
  @override
  Future<EmployeeManagementState> build() => _load();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<EmployeeMutationResult> create(EmployeeDraft draft) async {
    try {
      final response = await ApiClient.post('/employees', draft.toJson());
      if (response.statusCode != 201) {
        return EmployeeMutationResult(false, _message(response.body));
      }
      await refresh();
      return EmployeeMutationResult(
        true,
        '${draft.name} berhasil ditambahkan.',
      );
    } catch (_) {
      return const EmployeeMutationResult(
        false,
        'Karyawan belum dapat ditambahkan. Periksa koneksi server.',
      );
    }
  }

  Future<EmployeeMutationResult> updateEmployee(
    EmployeeProfile employee,
    EmployeeDraft draft,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/employees/${employee.id}',
        draft.toJson(),
      );
      if (response.statusCode != 200) {
        return EmployeeMutationResult(false, _message(response.body));
      }
      await refresh();
      return EmployeeMutationResult(true, '${draft.name} berhasil diperbarui.');
    } catch (_) {
      return const EmployeeMutationResult(
        false,
        'Data karyawan belum dapat diperbarui.',
      );
    }
  }

  Future<EmployeeMutationResult> delete(EmployeeProfile employee) async {
    try {
      final response = await ApiClient.delete('/employees/${employee.id}');
      if (response.statusCode != 204) {
        return EmployeeMutationResult(false, _message(response.body));
      }
      await refresh();
      return EmployeeMutationResult(true, '${employee.name} berhasil dihapus.');
    } catch (_) {
      return const EmployeeMutationResult(
        false,
        'Karyawan belum dapat dihapus. Nonaktifkan jika sudah memiliki absensi.',
      );
    }
  }

  Future<EmployeeManagementState> _load() async {
    final responses = await Future.wait([
      ApiClient.get('/employees?status=all&per_page=100'),
      ApiClient.get('/employees/options'),
    ]);
    if (responses.any((response) => response.statusCode != 200)) {
      final failed = responses.firstWhere(
        (response) => response.statusCode != 200,
      );
      throw StateError(_message(failed.body));
    }
    final employeesBody = Map<String, dynamic>.from(
      jsonDecode(responses[0].body) as Map,
    );
    final options = Map<String, dynamic>.from(
      jsonDecode(responses[1].body) as Map,
    );

    return EmployeeManagementState(
      employees: (employeesBody['data'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => EmployeeProfile.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      roles: (options['roles'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                EmployeeRoleOption.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      outlets: (options['outlets'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                EmployeeOutletOption.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      employmentStatuses: (options['employment_statuses'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                EmploymentStatusOption.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  String _message(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              return value.first.toString();
            }
          }
        }
        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {
      // Use the stable fallback below.
    }
    return 'Permintaan karyawan belum dapat diproses.';
  }
}

final employeeProvider =
    AsyncNotifierProvider<EmployeeNotifier, EmployeeManagementState>(
      EmployeeNotifier.new,
    );

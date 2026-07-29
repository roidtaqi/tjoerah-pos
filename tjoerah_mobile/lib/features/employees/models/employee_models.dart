class EmployeeRoleOption {
  const EmployeeRoleOption({
    required this.value,
    required this.label,
    required this.description,
    this.assignable = true,
  });

  factory EmployeeRoleOption.fromJson(Map<String, dynamic> json) {
    return EmployeeRoleOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      assignable: _asBool(json['assignable'], fallback: true),
    );
  }

  final String value;
  final String label;
  final String description;
  final bool assignable;
}

class EmployeeShiftOption {
  const EmployeeShiftOption({
    required this.id,
    required this.name,
    required this.startTime,
    required this.lateAfterTime,
    required this.endTime,
  });

  factory EmployeeShiftOption.fromJson(Map<String, dynamic> json) {
    return EmployeeShiftOption(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      lateAfterTime: json['late_after_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
    );
  }

  final int id;
  final String name;
  final String startTime;
  final String lateAfterTime;
  final String endTime;
}

class EmployeeOutletOption {
  const EmployeeOutletOption({
    required this.id,
    required this.name,
    required this.shifts,
  });

  factory EmployeeOutletOption.fromJson(Map<String, dynamic> json) {
    return EmployeeOutletOption(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      shifts: (json['attendance_shifts'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                EmployeeShiftOption.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  final int id;
  final String name;
  final List<EmployeeShiftOption> shifts;
}

class EmploymentStatusOption {
  const EmploymentStatusOption({required this.value, required this.label});

  factory EmploymentStatusOption.fromJson(Map<String, dynamic> json) {
    return EmploymentStatusOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }

  final String value;
  final String label;
}

class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.employeeNumber,
    required this.name,
    required this.email,
    required this.role,
    required this.outletId,
    required this.isActive,
    this.attendanceShiftId,
    this.outletName,
    this.shiftName,
    this.phone,
    this.position,
    this.employmentStatus = 'permanent',
    this.hireDate,
    this.birthDate,
    this.gender,
    this.identityNumber,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : const <String, dynamic>{};
    final outlet = json['outlet'] is Map
        ? Map<String, dynamic>.from(json['outlet'] as Map)
        : const <String, dynamic>{};
    final shift = json['attendance_shift'] is Map
        ? Map<String, dynamic>.from(json['attendance_shift'] as Map)
        : const <String, dynamic>{};
    return EmployeeProfile(
      id: _asInt(json['id']),
      employeeNumber: json['employee_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: user['email']?.toString() ?? json['email']?.toString() ?? '',
      role: user['role']?.toString() ?? 'cashier',
      outletId: _asInt(json['outlet_id']),
      attendanceShiftId: _nullableInt(json['attendance_shift_id']),
      outletName: outlet['name']?.toString(),
      shiftName: shift['name']?.toString(),
      phone: _nullableString(json['phone']),
      position: _nullableString(json['position']),
      employmentStatus: json['employment_status']?.toString() ?? 'permanent',
      hireDate: _nullableDate(json['hire_date']),
      birthDate: _nullableDate(json['birth_date']),
      gender: _nullableString(json['gender']),
      identityNumber: _nullableString(json['identity_number']),
      address: _nullableString(json['address']),
      emergencyContactName: _nullableString(json['emergency_contact_name']),
      emergencyContactPhone: _nullableString(json['emergency_contact_phone']),
      isActive: _asBool(json['is_active'], fallback: true),
    );
  }

  final int id;
  final String employeeNumber;
  final String name;
  final String email;
  final String role;
  final int outletId;
  final int? attendanceShiftId;
  final String? outletName;
  final String? shiftName;
  final String? phone;
  final String? position;
  final String employmentStatus;
  final DateTime? hireDate;
  final DateTime? birthDate;
  final String? gender;
  final String? identityNumber;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final bool isActive;
}

class EmployeeDraft {
  const EmployeeDraft({
    required this.employeeNumber,
    required this.name,
    required this.email,
    required this.role,
    required this.outletId,
    required this.employmentStatus,
    required this.isActive,
    this.attendanceShiftId,
    this.phone,
    this.position,
    this.hireDate,
    this.birthDate,
    this.gender,
    this.identityNumber,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.password,
    this.pin,
  });

  final String employeeNumber;
  final String name;
  final String email;
  final String role;
  final int outletId;
  final int? attendanceShiftId;
  final String? phone;
  final String? position;
  final String employmentStatus;
  final DateTime? hireDate;
  final DateTime? birthDate;
  final String? gender;
  final String? identityNumber;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? password;
  final String? pin;
  final bool isActive;

  Map<String, dynamic> toJson() {
    return {
      'employee_number': employeeNumber,
      'name': name,
      'email': email,
      'role': role,
      'outlet_id': outletId,
      'attendance_shift_id': attendanceShiftId,
      'phone': phone,
      'position': position,
      'employment_status': employmentStatus,
      'hire_date': _dateOnly(hireDate),
      'birth_date': _dateOnly(birthDate),
      'gender': gender,
      'identity_number': identityNumber,
      'address': address,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      if (password != null && password!.isNotEmpty) 'password': password,
      if (pin != null && pin!.isNotEmpty) 'pin': pin,
      'is_active': isActive,
    };
  }
}

int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  return value is int ? value : int.tryParse('$value');
}

bool _asBool(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
}

String? _nullableString(dynamic value) {
  final string = value?.toString().trim();
  return string == null || string.isEmpty ? null : string;
}

DateTime? _nullableDate(dynamic value) {
  final string = value?.toString();
  return string == null ? null : DateTime.tryParse(string);
}

String? _dateOnly(DateTime? value) {
  if (value == null) return null;
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

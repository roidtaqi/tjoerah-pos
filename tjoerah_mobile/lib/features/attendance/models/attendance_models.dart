class AttendanceEmployee {
  const AttendanceEmployee({
    required this.id,
    required this.name,
    this.employeeNumber,
    this.position,
    this.outletId,
  });

  factory AttendanceEmployee.fromJson(Map<String, dynamic> json) {
    return AttendanceEmployee(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      employeeNumber: _nullableString(json['employee_number']),
      position: _nullableString(json['position']),
      outletId: _nullableInt(json['outlet_id']),
    );
  }

  final int id;
  final String name;
  final String? employeeNumber;
  final String? position;
  final int? outletId;
}

class AttendanceOutlet {
  const AttendanceOutlet({
    required this.id,
    required this.name,
    this.timezone = 'Asia/Makassar',
  });

  factory AttendanceOutlet.fromJson(Map<String, dynamic> json) {
    return AttendanceOutlet(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      timezone: json['timezone']?.toString() ?? 'Asia/Makassar',
    );
  }

  final int id;
  final String name;
  final String timezone;
}

class AttendancePolicy {
  const AttendancePolicy({
    required this.outletId,
    this.timezone = 'Asia/Makassar',
    this.workStartTime = '08:00',
    this.workEndTime = '17:00',
    this.lateToleranceMinutes = 10,
    this.checkInOpenMinutes = 60,
    this.latitude,
    this.longitude,
    this.geofenceRadiusMeters = 100,
    this.maximumAccuracyMeters = 100,
    this.requireCheckInPhoto = true,
    this.requireCheckOutPhoto = true,
    this.allowOutsideWithReason = true,
    this.photoRetentionDays = 180,
    this.isActive = true,
  });

  factory AttendancePolicy.fromJson(Map<String, dynamic> json) {
    return AttendancePolicy(
      outletId: _asInt(json['outlet_id']),
      timezone: json['timezone']?.toString() ?? 'Asia/Makassar',
      workStartTime: json['work_start_time']?.toString() ?? '08:00',
      workEndTime: json['work_end_time']?.toString() ?? '17:00',
      lateToleranceMinutes: _asInt(
        json['late_tolerance_minutes'],
        fallback: 10,
      ),
      checkInOpenMinutes: _asInt(json['check_in_open_minutes'], fallback: 60),
      latitude: _nullableDouble(json['latitude']),
      longitude: _nullableDouble(json['longitude']),
      geofenceRadiusMeters: _asInt(
        json['geofence_radius_meters'],
        fallback: 100,
      ),
      maximumAccuracyMeters: _asInt(
        json['maximum_accuracy_meters'],
        fallback: 100,
      ),
      requireCheckInPhoto: _asBool(
        json['require_check_in_photo'],
        fallback: true,
      ),
      requireCheckOutPhoto: _asBool(
        json['require_check_out_photo'],
        fallback: true,
      ),
      allowOutsideWithReason: _asBool(
        json['allow_outside_with_reason'],
        fallback: true,
      ),
      photoRetentionDays: _asInt(json['photo_retention_days'], fallback: 180),
      isActive: _asBool(json['is_active'], fallback: true),
    );
  }

  final int outletId;
  final String timezone;
  final String workStartTime;
  final String workEndTime;
  final int lateToleranceMinutes;
  final int checkInOpenMinutes;
  final double? latitude;
  final double? longitude;
  final int geofenceRadiusMeters;
  final int maximumAccuracyMeters;
  final bool requireCheckInPhoto;
  final bool requireCheckOutPhoto;
  final bool allowOutsideWithReason;
  final int photoRetentionDays;
  final bool isActive;

  Map<String, dynamic> toJson() {
    return {
      'outlet_id': outletId,
      'timezone': timezone,
      'work_start_time': workStartTime,
      'work_end_time': workEndTime,
      'late_tolerance_minutes': lateToleranceMinutes,
      'check_in_open_minutes': checkInOpenMinutes,
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': geofenceRadiusMeters,
      'maximum_accuracy_meters': maximumAccuracyMeters,
      'require_check_in_photo': requireCheckInPhoto,
      'require_check_out_photo': requireCheckOutPhoto,
      'allow_outside_with_reason': allowOutsideWithReason,
      'photo_retention_days': photoRetentionDays,
      'is_active': isActive,
    };
  }
}

class EmployeeScheduleModel {
  const EmployeeScheduleModel({
    required this.id,
    required this.employeeId,
    required this.outletId,
    required this.workDate,
    required this.startAt,
    required this.endAt,
    required this.shiftName,
    required this.status,
    this.notes,
    this.employee,
  });

  factory EmployeeScheduleModel.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    return EmployeeScheduleModel(
      id: _asInt(json['id']),
      employeeId: _asInt(json['employee_id']),
      outletId: _asInt(json['outlet_id']),
      workDate: DateTime.parse(json['work_date'].toString()),
      startAt: DateTime.parse(json['start_at'].toString()),
      endAt: DateTime.parse(json['end_at'].toString()),
      shiftName: json['shift_name']?.toString() ?? 'Reguler',
      status: json['status']?.toString() ?? 'scheduled',
      notes: _nullableString(json['notes']),
      employee: employee is Map
          ? AttendanceEmployee.fromJson(Map<String, dynamic>.from(employee))
          : null,
    );
  }

  final int id;
  final int employeeId;
  final int outletId;
  final DateTime workDate;
  final DateTime startAt;
  final DateTime endAt;
  final String shiftName;
  final String status;
  final String? notes;
  final AttendanceEmployee? employee;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.outletId,
    this.workDate,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.checkInAt,
    this.checkOutAt,
    this.punctualityStatus,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.reviewStatus = 'approved',
    this.reviewNotes,
    this.checkInAccuracyMeters,
    this.checkInDistanceMeters,
    this.checkInOutsideGeofence = false,
    this.checkInIsMock = false,
    this.hasCheckInPhoto = false,
    this.hasCheckOutPhoto = false,
    this.anomalyFlags = const [],
    this.employee,
    this.outlet,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    final outlet = json['outlet'];
    return AttendanceRecord(
      id: _asInt(json['id']),
      employeeId: _asInt(json['employee_id']),
      outletId: _asInt(json['outlet_id']),
      workDate: _nullableDate(json['work_date']),
      scheduledStartAt: _nullableDate(json['scheduled_start_at']),
      scheduledEndAt: _nullableDate(json['scheduled_end_at']),
      checkInAt: _nullableDate(json['check_in_at']),
      checkOutAt: _nullableDate(json['check_out_at']),
      punctualityStatus: _nullableString(json['punctuality_status']),
      lateMinutes: _asInt(json['late_minutes']),
      earlyLeaveMinutes: _asInt(json['early_leave_minutes']),
      reviewStatus: json['review_status']?.toString() ?? 'approved',
      reviewNotes: _nullableString(json['review_notes']),
      checkInAccuracyMeters: _nullableDouble(json['check_in_accuracy_meters']),
      checkInDistanceMeters: _nullableDouble(json['check_in_distance_meters']),
      checkInOutsideGeofence: _asBool(json['check_in_outside_geofence']),
      checkInIsMock: _asBool(json['check_in_is_mock']),
      hasCheckInPhoto: _asBool(json['has_check_in_photo']),
      hasCheckOutPhoto: _asBool(json['has_check_out_photo']),
      anomalyFlags:
          (json['anomaly_flags'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
      employee: employee is Map
          ? AttendanceEmployee.fromJson(Map<String, dynamic>.from(employee))
          : null,
      outlet: outlet is Map
          ? AttendanceOutlet.fromJson(Map<String, dynamic>.from(outlet))
          : null,
    );
  }

  final int id;
  final int employeeId;
  final int outletId;
  final DateTime? workDate;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String? punctualityStatus;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final String reviewStatus;
  final String? reviewNotes;
  final double? checkInAccuracyMeters;
  final double? checkInDistanceMeters;
  final bool checkInOutsideGeofence;
  final bool checkInIsMock;
  final bool hasCheckInPhoto;
  final bool hasCheckOutPhoto;
  final List<String> anomalyFlags;
  final AttendanceEmployee? employee;
  final AttendanceOutlet? outlet;
}

class AttendanceContextModel {
  const AttendanceContextModel({
    required this.employee,
    required this.outlet,
    required this.policy,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.serverTime,
    this.schedule,
    this.activeAttendance,
    this.recentAttendance = const [],
    this.pendingOfflineCount = 0,
  });

  factory AttendanceContextModel.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'];
    final active = json['active_attendance'];
    return AttendanceContextModel(
      employee: AttendanceEmployee.fromJson(
        Map<String, dynamic>.from(json['employee'] as Map),
      ),
      outlet: AttendanceOutlet.fromJson(
        Map<String, dynamic>.from(json['outlet'] as Map),
      ),
      policy: AttendancePolicy.fromJson(
        Map<String, dynamic>.from(json['policy'] as Map),
      ),
      schedule: schedule is Map
          ? EmployeeScheduleModel.fromJson(Map<String, dynamic>.from(schedule))
          : null,
      scheduledStartAt: DateTime.parse(json['scheduled_start_at'].toString()),
      scheduledEndAt: DateTime.parse(json['scheduled_end_at'].toString()),
      activeAttendance: active is Map
          ? AttendanceRecord.fromJson(Map<String, dynamic>.from(active))
          : null,
      recentAttendance: (json['recent_attendance'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => AttendanceRecord.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      serverTime: DateTime.parse(json['server_time'].toString()),
    );
  }

  final AttendanceEmployee employee;
  final AttendanceOutlet outlet;
  final AttendancePolicy policy;
  final EmployeeScheduleModel? schedule;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final AttendanceRecord? activeAttendance;
  final List<AttendanceRecord> recentAttendance;
  final DateTime serverTime;
  final int pendingOfflineCount;

  AttendanceContextModel copyWith({
    AttendanceRecord? activeAttendance,
    bool clearActiveAttendance = false,
    List<AttendanceRecord>? recentAttendance,
    int? pendingOfflineCount,
    DateTime? serverTime,
  }) {
    return AttendanceContextModel(
      employee: employee,
      outlet: outlet,
      policy: policy,
      schedule: schedule,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      activeAttendance: clearActiveAttendance
          ? null
          : activeAttendance ?? this.activeAttendance,
      recentAttendance: recentAttendance ?? this.recentAttendance,
      serverTime: serverTime ?? this.serverTime,
      pendingOfflineCount: pendingOfflineCount ?? this.pendingOfflineCount,
    );
  }
}

class AttendanceSummary {
  const AttendanceSummary({
    this.total = 0,
    this.onTime = 0,
    this.late = 0,
    this.pendingReview = 0,
    this.earlyLeave = 0,
    this.lateMinutes = 0,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      total: _asInt(json['total']),
      onTime: _asInt(json['on_time']),
      late: _asInt(json['late']),
      pendingReview: _asInt(json['pending_review']),
      earlyLeave: _asInt(json['early_leave']),
      lateMinutes: _asInt(json['late_minutes']),
    );
  }

  final int total;
  final int onTime;
  final int late;
  final int pendingReview;
  final int earlyLeave;
  final int lateMinutes;
}

class AttendanceSubmissionResult {
  const AttendanceSubmissionResult({
    required this.isSuccess,
    required this.message,
    this.attendance,
    this.isQueued = false,
  });

  final bool isSuccess;
  final String message;
  final AttendanceRecord? attendance;
  final bool isQueued;
}

int _asInt(dynamic value, {int fallback = 0}) {
  return value is int ? value : int.tryParse('$value') ?? fallback;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

double? _nullableDouble(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return value is num ? value.toDouble() : double.tryParse('$value');
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value == '1' || value.toLowerCase() == 'true') return true;
    if (value == '0' || value.toLowerCase() == 'false') return false;
  }
  return fallback;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _nullableDate(dynamic value) {
  final text = _nullableString(value);
  return text == null ? null : DateTime.tryParse(text);
}

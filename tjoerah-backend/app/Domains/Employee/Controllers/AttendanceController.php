<?php

namespace App\Domains\Employee\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Employee\Models\AttendanceAudit;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\AttendanceShift;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\EmployeeSchedule;
use App\Domains\Employee\Services\AttendanceService;
use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AttendanceController extends Controller
{
    public function __construct(private readonly AttendanceService $attendanceService) {}

    public function context(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
        ]);

        return response()->json($this->attendanceService->context(
            $request->user(),
            isset($validated['outlet_id']) ? (int) $validated['outlet_id'] : null,
        ));
    }

    public function myHistory(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);
        $employee = $this->attendanceService->resolveEmployee(
            $request->user(),
            isset($validated['outlet_id']) ? (int) $validated['outlet_id'] : null,
        );

        return $employee->attendanceLogs()
            ->with(['outlet', 'schedule', 'attendanceShift'])
            ->latest('check_in_at')
            ->paginate($request->integer('per_page', 30));
    }

    public function outlets(Request $request)
    {
        $query = Outlet::query()
            ->where('is_active', true)
            ->orderBy('name');

        if ($request->user()->company_id) {
            $query->where('company_id', $request->user()->company_id);
        } else {
            $query->whereHas('users', fn ($users) => $users->whereKey($request->user()->id));
        }

        return response()->json($query->get());
    }

    public function checkIn(Request $request)
    {
        $validated = $request->validate($this->captureRules());
        $attendance = $this->attendanceService->checkIn(
            $request->user(),
            $validated,
            $request->file('photo'),
        );

        return response()->json([
            'message' => $this->resultMessage($attendance, 'masuk'),
            'attendance' => $attendance,
            'server_time' => now()->utc(),
        ], 201);
    }

    public function checkOut(Request $request)
    {
        $validated = $request->validate([
            ...$this->captureRules(),
            'attendance_log_id' => 'nullable|integer|exists:attendance_logs,id',
        ]);
        $attendance = $this->attendanceService->checkOut(
            $request->user(),
            $validated,
            $request->file('photo'),
        );

        return response()->json([
            'message' => $this->resultMessage($attendance, 'pulang'),
            'attendance' => $attendance,
            'server_time' => now()->utc(),
        ]);
    }

    public function photo(Request $request, AttendanceLog $attendance, string $type)
    {
        abort_unless(in_array($type, ['check-in', 'check-out'], true), 404);
        $this->ensureAttendanceAccessible($request, $attendance, allowSelf: true);
        $path = $type === 'check-in'
            ? $attendance->getRawOriginal('check_in_photo_path')
            : $attendance->getRawOriginal('check_out_photo_path');
        abort_if(blank($path) || ! Storage::disk('local')->exists($path), 404);

        return Storage::disk('local')->response($path, basename($path), [
            'Cache-Control' => 'private, max-age=300',
        ]);
    }

    public function report(Request $request)
    {
        $validated = $request->validate([
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'employee_id' => 'nullable|integer|exists:employees,id',
            'status' => ['nullable', Rule::in(['all', 'on_time', 'late', 'pending_review', 'early_leave'])],
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);

        [$dateFrom, $dateTo] = $this->reportDates($validated);
        $query = $this->reportQuery($request, $validated, $dateFrom, $dateTo);
        $summaryQuery = clone $query;

        $summary = [
            'total' => (clone $summaryQuery)->count(),
            'on_time' => (clone $summaryQuery)->where('punctuality_status', 'on_time')->count(),
            'late' => (clone $summaryQuery)->where('punctuality_status', 'late')->count(),
            'pending_review' => (clone $summaryQuery)->where('review_status', 'pending')->count(),
            'early_leave' => (clone $summaryQuery)->where('early_leave_minutes', '>', 0)->count(),
            'late_minutes' => (int) (clone $summaryQuery)->sum('late_minutes'),
        ];

        return response()->json([
            'summary' => $summary,
            'records' => $query->latest('check_in_at')
                ->paginate($request->integer('per_page', 50)),
        ]);
    }

    public function export(Request $request)
    {
        $validated = $request->validate([
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'employee_id' => 'nullable|integer|exists:employees,id',
            'status' => ['nullable', Rule::in(['all', 'on_time', 'late', 'pending_review', 'early_leave'])],
        ]);
        [$dateFrom, $dateTo] = $this->reportDates($validated);
        $records = $this->reportQuery($request, $validated, $dateFrom, $dateTo)
            ->orderBy('check_in_at')
            ->get();

        $handle = fopen('php://temp', 'r+');
        fputcsv($handle, [
            'Tanggal',
            'Karyawan',
            'Outlet',
            'Shift',
            'Jadwal masuk',
            'Mulai terlambat',
            'Absen masuk',
            'Absen pulang',
            'Status',
            'Menit terlambat',
            'Menit pulang cepat',
            'Pemeriksaan',
        ]);
        foreach ($records as $record) {
            fputcsv($handle, [
                $record->work_date?->format('Y-m-d'),
                $record->employee?->name,
                $record->outlet?->name,
                $record->attendanceShift?->name ?? $record->schedule?->shift_name,
                $record->scheduled_start_at?->toIso8601String(),
                $record->scheduled_late_after_at?->toIso8601String(),
                $record->check_in_at?->toIso8601String(),
                $record->check_out_at?->toIso8601String(),
                $record->punctuality_status,
                $record->late_minutes,
                $record->early_leave_minutes,
                $record->review_status,
            ]);
        }
        rewind($handle);
        $csv = stream_get_contents($handle);
        fclose($handle);

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => sprintf(
                'attachment; filename="laporan-absensi-%s-%s.csv"',
                $dateFrom,
                $dateTo,
            ),
        ]);
    }

    public function policy(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);

        return response()->json($this->attendanceService->policyForOutlet($outlet));
    }

    public function updatePolicy(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'timezone' => 'required|timezone',
            'work_start_time' => ['required', 'date_format:H:i'],
            'work_end_time' => ['required', 'date_format:H:i'],
            'late_tolerance_minutes' => 'required|integer|min:0|max:240',
            'check_in_open_minutes' => 'required|integer|min:0|max:720',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'geofence_radius_meters' => 'required|integer|min:20|max:5000',
            'maximum_accuracy_meters' => 'required|integer|min:10|max:2000',
            'require_check_in_photo' => 'required|boolean',
            'require_check_out_photo' => 'required|boolean',
            'allow_outside_with_reason' => 'required|boolean',
            'photo_retention_days' => 'required|integer|min:30|max:3650',
            'is_active' => 'required|boolean',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $policy = AttendancePolicy::updateOrCreate(
            ['outlet_id' => $outlet->id],
            [
                ...$validated,
                'company_id' => $request->user()->company_id ?? $outlet->company_id,
            ],
        );

        return response()->json($policy);
    }

    public function attendanceShifts(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);

        return response()->json(
            AttendanceShift::withCount('employees')
                ->where('outlet_id', $outlet->id)
                ->orderBy('sort_order')
                ->orderBy('start_time')
                ->get(),
        );
    }

    public function storeAttendanceShift(Request $request)
    {
        $validated = $request->validate($this->attendanceShiftRules());
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $this->validateAttendanceShiftTimes($validated);
        $this->ensureUniqueAttendanceShiftName(
            $outlet->id,
            $validated['name'],
        );

        $shift = AttendanceShift::create([
            ...$validated,
            'company_id' => $request->user()->company_id ?? $outlet->company_id,
        ]);

        return response()->json($shift->loadCount('employees'), 201);
    }

    public function updateAttendanceShift(
        Request $request,
        AttendanceShift $attendanceShift,
    ) {
        $this->ensureAttendanceShiftAccessible($request, $attendanceShift);
        $validated = $request->validate($this->attendanceShiftRules(partial: true));
        $merged = [
            ...$attendanceShift->only([
                'outlet_id',
                'name',
                'start_time',
                'late_after_time',
                'end_time',
                'check_in_open_minutes',
                'is_active',
                'sort_order',
            ]),
            ...$validated,
        ];
        $outlet = $this->accessibleOutlet($request, (int) $merged['outlet_id']);
        $this->validateAttendanceShiftTimes($merged);
        $this->ensureUniqueAttendanceShiftName(
            $outlet->id,
            $merged['name'],
            $attendanceShift->id,
        );
        abort_if(
            isset($validated['outlet_id'])
                && $attendanceShift->outlet_id !== $outlet->id,
            422,
            'Outlet shift tidak dapat dipindahkan.',
        );

        $attendanceShift->update($validated);

        return response()->json($attendanceShift->fresh()->loadCount('employees'));
    }

    public function destroyAttendanceShift(
        Request $request,
        AttendanceShift $attendanceShift,
    ) {
        $this->ensureAttendanceShiftAccessible($request, $attendanceShift);
        abort_if(
            $attendanceShift->employees()->exists()
                || $attendanceShift->schedules()->exists()
                || $attendanceShift->attendanceLogs()->exists(),
            422,
            'Shift sudah digunakan. Nonaktifkan shift agar riwayat tetap terjaga.',
        );
        $attendanceShift->delete();

        return response()->noContent();
    }

    public function assignAttendanceShifts(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'assignments' => 'required|array|min:1',
            'assignments.*.employee_id' => 'required|integer|distinct|exists:employees,id',
            'assignments.*.attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);

        DB::transaction(function () use ($request, $validated, $outlet): void {
            foreach ($validated['assignments'] as $assignment) {
                $employee = $this->accessibleEmployee($request, (int) $assignment['employee_id']);
                abort_unless(
                    $employee->outlet_id === $outlet->id,
                    422,
                    'Semua karyawan harus berasal dari outlet yang dipilih.',
                );
                $shiftId = $assignment['attendance_shift_id'] ?? null;
                if ($shiftId) {
                    $shift = $this->accessibleAttendanceShift($request, (int) $shiftId);
                    abort_unless(
                        $shift->outlet_id === $outlet->id,
                        422,
                        'Shift dan karyawan harus berasal dari outlet yang sama.',
                    );
                }
                $employee->update(['attendance_shift_id' => $shiftId]);
            }
        });

        return response()->json(
            Employee::with('attendanceShift')
                ->where('outlet_id', $outlet->id)
                ->orderBy('name')
                ->get(),
        );
    }

    public function schedules(Request $request)
    {
        $validated = $request->validate([
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'employee_id' => 'nullable|integer|exists:employees,id',
        ]);
        [$dateFrom, $dateTo] = $this->reportDates($validated);

        return EmployeeSchedule::with(['employee', 'outlet', 'attendanceShift'])
            ->whereDate('work_date', '>=', $dateFrom)
            ->whereDate('work_date', '<=', $dateTo)
            ->when($request->user()->company_id, function ($query, $companyId) {
                $query->whereHas('employee', fn ($employee) => $employee->where('company_id', $companyId));
            }, function ($query) use ($request) {
                $query->whereIn('outlet_id', $this->assignedOutletIds($request));
            })
            ->when($validated['outlet_id'] ?? null, fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($validated['employee_id'] ?? null, fn ($query, $employeeId) => $query->where('employee_id', $employeeId))
            ->orderBy('start_at')
            ->get();
    }

    public function storeSchedule(Request $request)
    {
        $validated = $request->validate($this->scheduleRules());
        $employee = $this->accessibleEmployee($request, (int) $validated['employee_id']);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        abort_if($employee->outlet_id && $employee->outlet_id !== $outlet->id, 422, 'Karyawan tidak terhubung dengan outlet tersebut.');

        $scheduleData = $this->prepareScheduleData($request, $validated, $outlet);
        $schedule = EmployeeSchedule::create([
            ...$scheduleData,
            'created_by' => $request->user()->id,
        ]);

        return response()->json(
            $schedule->load(['employee', 'outlet', 'attendanceShift']),
            201,
        );
    }

    public function updateSchedule(Request $request, EmployeeSchedule $schedule)
    {
        $this->ensureScheduleAccessible($request, $schedule);
        $validated = $request->validate($this->scheduleRules(partial: true));
        if (isset($validated['employee_id'])) {
            $employee = $this->accessibleEmployee($request, (int) $validated['employee_id']);
        } else {
            $employee = $schedule->employee;
        }
        if (isset($validated['outlet_id'])) {
            $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        } else {
            $outlet = $schedule->outlet;
        }
        abort_if(
            $employee?->outlet_id && $employee->outlet_id !== $outlet?->id,
            422,
            'Karyawan tidak terhubung dengan outlet tersebut.',
        );
        $scheduleData = $this->prepareScheduleData(
            $request,
            [
                ...$schedule->only([
                    'employee_id',
                    'outlet_id',
                    'attendance_shift_id',
                    'work_date',
                    'start_at',
                    'late_after_at',
                    'end_at',
                    'shift_name',
                    'status',
                    'notes',
                ]),
                ...$validated,
            ],
            $outlet,
        );
        $schedule->update($scheduleData);

        return response()->json(
            $schedule->fresh()->load(['employee', 'outlet', 'attendanceShift']),
        );
    }

    public function destroySchedule(Request $request, EmployeeSchedule $schedule)
    {
        $this->ensureScheduleAccessible($request, $schedule);
        abort_if(
            AttendanceLog::where('employee_schedule_id', $schedule->id)->exists(),
            422,
            'Jadwal sudah memiliki catatan absensi dan tidak dapat dihapus.',
        );
        $schedule->delete();

        return response()->noContent();
    }

    public function review(Request $request, AttendanceLog $attendance)
    {
        $this->ensureAttendanceAccessible($request, $attendance);
        $validated = $request->validate([
            'review_status' => ['required', Rule::in(['approved', 'rejected', 'pending'])],
            'review_notes' => 'required|string|max:2000',
            'check_in_at' => 'nullable|date',
            'check_out_at' => 'nullable|date|after:check_in_at',
        ]);
        $before = $attendance->only([
            'check_in_at',
            'check_out_at',
            'punctuality_status',
            'late_minutes',
            'early_leave_minutes',
            'review_status',
            'review_notes',
        ]);

        $changes = [
            'review_status' => $validated['review_status'],
            'review_notes' => $validated['review_notes'],
            'reviewed_by' => $request->user()->id,
            'reviewed_at' => now(),
        ];
        if (isset($validated['check_in_at'])) {
            $checkIn = CarbonImmutable::parse($validated['check_in_at'])->utc();
            $changes['check_in_at'] = $checkIn;
            if ($attendance->scheduled_start_at) {
                $deadline = $attendance->scheduled_late_after_at
                    ? CarbonImmutable::instance($attendance->scheduled_late_after_at)
                    : CarbonImmutable::instance($attendance->scheduled_start_at)->addMinutes(
                        $attendance->outlet?->attendancePolicy?->late_tolerance_minutes ?? 0,
                    );
                [$punctuality, $lateMinutes] = $this->attendanceService->lateness(
                    $checkIn,
                    $deadline,
                );
                $changes += [
                    'late_minutes' => $lateMinutes,
                    'punctuality_status' => $punctuality,
                ];
            }
        }
        if (isset($validated['check_out_at'])) {
            $checkOut = CarbonImmutable::parse($validated['check_out_at'])->utc();
            $changes['check_out_at'] = $checkOut;
            if ($attendance->scheduled_end_at) {
                $scheduledEnd = CarbonImmutable::instance($attendance->scheduled_end_at);
                $changes['early_leave_minutes'] = max(
                    0,
                    intdiv($scheduledEnd->getTimestamp() - $checkOut->getTimestamp(), 60),
                );
            }
        }
        $attendance->update($changes);
        AttendanceAudit::create([
            'attendance_log_id' => $attendance->id,
            'actor_id' => $request->user()->id,
            'action' => 'reviewed',
            'before' => $before,
            'after' => $attendance->fresh()->only(array_keys($before)),
            'reason' => $validated['review_notes'],
        ]);

        return response()->json($attendance->fresh()->load([
            'employee',
            'outlet',
            'attendanceShift',
            'reviewer',
            'audits.actor',
        ]));
    }

    private function captureRules(): array
    {
        return [
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'photo' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'accuracy_meters' => 'required|numeric|min:0|max:100000',
            'is_mock' => 'nullable|boolean',
            'device_captured_at' => 'required|date',
            'device_id' => 'required|string|max:255',
            'request_id' => 'required|uuid',
            'outside_reason' => 'nullable|string|max:1000',
            'notes' => 'nullable|string|max:2000',
            'source' => 'nullable|string|max:50',
        ];
    }

    private function scheduleRules(bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return [
            'employee_id' => [$required, 'integer', 'exists:employees,id'],
            'outlet_id' => [$required, 'integer', 'exists:outlets,id'],
            'work_date' => [$required, 'date'],
            'start_at' => [$required, 'date'],
            'late_after_at' => ['nullable', 'date'],
            'end_at' => [$required, 'date', 'after:start_at'],
            'attendance_shift_id' => ['nullable', 'integer', 'exists:attendance_shifts,id'],
            'shift_name' => [$required, 'string', 'max:100'],
            'status' => [$required, Rule::in(['scheduled', 'leave', 'sick', 'off', 'cancelled'])],
            'notes' => 'nullable|string|max:2000',
        ];
    }

    private function attendanceShiftRules(bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return [
            'outlet_id' => [$required, 'integer', 'exists:outlets,id'],
            'name' => [$required, 'string', 'max:100'],
            'start_time' => [$required, 'date_format:H:i'],
            'late_after_time' => [$required, 'date_format:H:i'],
            'end_time' => [$required, 'date_format:H:i'],
            'check_in_open_minutes' => [$required, 'integer', 'min:0', 'max:720'],
            'is_active' => [$required, 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:999'],
        ];
    }

    private function validateAttendanceShiftTimes(array $data): void
    {
        $start = $this->minutesFromTime($data['start_time']);
        $lateAfter = $this->minutesFromTime($data['late_after_time']);
        $end = $this->minutesFromTime($data['end_time']);
        if ($end <= $start) {
            $end += 1440;
        }
        if ($lateAfter < $start) {
            $lateAfter += 1440;
        }
        if ($lateAfter > $end) {
            throw ValidationException::withMessages([
                'late_after_time' => 'Batas terlambat harus berada di antara jam mulai dan selesai.',
            ]);
        }
    }

    private function ensureUniqueAttendanceShiftName(
        int $outletId,
        string $name,
        ?int $ignoreId = null,
    ): void {
        $exists = AttendanceShift::where('outlet_id', $outletId)
            ->whereRaw('LOWER(name) = ?', [strtolower(trim($name))])
            ->when($ignoreId, fn ($query, $id) => $query->where('id', '!=', $id))
            ->exists();
        if ($exists) {
            throw ValidationException::withMessages([
                'name' => 'Nama shift sudah digunakan pada outlet ini.',
            ]);
        }
    }

    private function prepareScheduleData(
        Request $request,
        array $data,
        Outlet $outlet,
    ): array {
        $policy = $this->attendanceService->policyForOutlet($outlet);
        $shiftId = $data['attendance_shift_id'] ?? null;
        if ($shiftId) {
            $shift = $this->accessibleAttendanceShift($request, (int) $shiftId);
            abort_unless(
                $shift->outlet_id === $outlet->id,
                422,
                'Shift dan jadwal harus berasal dari outlet yang sama.',
            );
            $window = $this->attendanceService->shiftWindowForDate(
                $shift,
                CarbonImmutable::parse($data['work_date'])->toDateString(),
                $policy->timezone,
            );
            $data = [
                ...$data,
                'start_at' => $window['start'],
                'late_after_at' => $window['late_after'],
                'end_at' => $window['end'],
                'shift_name' => $shift->name,
            ];
        } else {
            $start = CarbonImmutable::parse($data['start_at'])->utc();
            $end = CarbonImmutable::parse($data['end_at'])->utc();
            $lateAfter = filled($data['late_after_at'] ?? null)
                ? CarbonImmutable::parse($data['late_after_at'])->utc()
                : $start->addMinutes($policy->late_tolerance_minutes);
            if ($lateAfter->lessThan($start) || $lateAfter->greaterThan($end)) {
                throw ValidationException::withMessages([
                    'late_after_at' => 'Batas terlambat harus berada di antara jam mulai dan selesai.',
                ]);
            }
            $data = [
                ...$data,
                'start_at' => $start,
                'late_after_at' => $lateAfter,
                'end_at' => $end,
            ];
        }

        return $data;
    }

    private function minutesFromTime(string $time): int
    {
        [$hour, $minute] = array_map('intval', explode(':', $time));

        return ($hour * 60) + $minute;
    }

    private function reportDates(array $validated): array
    {
        $dateFrom = CarbonImmutable::parse($validated['date_from'] ?? now()->startOfMonth())->toDateString();
        $dateTo = CarbonImmutable::parse($validated['date_to'] ?? now()->endOfMonth())->toDateString();

        return [$dateFrom, $dateTo];
    }

    private function reportQuery(
        Request $request,
        array $validated,
        string $dateFrom,
        string $dateTo,
    ): Builder {
        return AttendanceLog::with(['employee', 'outlet', 'schedule', 'attendanceShift', 'reviewer'])
            ->whereDate('work_date', '>=', $dateFrom)
            ->whereDate('work_date', '<=', $dateTo)
            ->when($request->user()->company_id, function ($query, $companyId) {
                $query->whereHas('employee', fn ($employee) => $employee->where('company_id', $companyId));
            }, function ($query) use ($request) {
                $query->whereIn('outlet_id', $this->assignedOutletIds($request));
            })
            ->when($validated['outlet_id'] ?? null, fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($validated['employee_id'] ?? null, fn ($query, $employeeId) => $query->where('employee_id', $employeeId))
            ->when($validated['status'] ?? null, function ($query, $status) {
                if ($status === 'on_time' || $status === 'late') {
                    $query->where('punctuality_status', $status);
                } elseif ($status === 'pending_review') {
                    $query->where('review_status', 'pending');
                } elseif ($status === 'early_leave') {
                    $query->where('early_leave_minutes', '>', 0);
                }
            });
    }

    private function accessibleOutlet(Request $request, int $outletId): Outlet
    {
        return Outlet::query()
            ->when($request->user()->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when(! $request->user()->company_id, fn ($query) => $query->whereIn('id', $this->assignedOutletIds($request)))
            ->findOrFail($outletId);
    }

    private function accessibleEmployee(Request $request, int $employeeId): Employee
    {
        return Employee::query()
            ->when($request->user()->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when(! $request->user()->company_id, fn ($query) => $query->whereIn('outlet_id', $this->assignedOutletIds($request)))
            ->findOrFail($employeeId);
    }

    private function accessibleAttendanceShift(
        Request $request,
        int $attendanceShiftId,
    ): AttendanceShift {
        return AttendanceShift::query()
            ->when(
                $request->user()->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
            )
            ->when(
                ! $request->user()->company_id,
                fn ($query) => $query->whereIn('outlet_id', $this->assignedOutletIds($request)),
            )
            ->findOrFail($attendanceShiftId);
    }

    private function ensureAttendanceShiftAccessible(
        Request $request,
        AttendanceShift $attendanceShift,
    ): void {
        abort_if(
            $request->user()->company_id
                ? $attendanceShift->company_id !== $request->user()->company_id
                : ! in_array($attendanceShift->outlet_id, $this->assignedOutletIds($request), true),
            404,
        );
    }

    private function ensureAttendanceAccessible(
        Request $request,
        AttendanceLog $attendance,
        bool $allowSelf = false,
    ): void {
        $attendance->loadMissing(['employee', 'outlet.attendancePolicy']);
        if ($allowSelf && $attendance->employee?->user_id === $request->user()->id) {
            return;
        }
        abort_if(
            $request->user()->company_id
                ? $attendance->employee?->company_id !== $request->user()->company_id
                : ! in_array($attendance->outlet_id, $this->assignedOutletIds($request), true),
            404,
        );
        abort_unless($this->isManager($request), 403);
    }

    private function ensureScheduleAccessible(Request $request, EmployeeSchedule $schedule): void
    {
        $schedule->loadMissing('employee');
        abort_if(
            $request->user()->company_id
                ? $schedule->employee?->company_id !== $request->user()->company_id
                : ! in_array($schedule->outlet_id, $this->assignedOutletIds($request), true),
            404,
        );
    }

    /**
     * @return array<int, int>
     */
    private function assignedOutletIds(Request $request): array
    {
        return $request->user()->outlets()
            ->pluck('outlets.id')
            ->map(fn ($id) => (int) $id)
            ->all();
    }

    private function isManager(Request $request): bool
    {
        $roles = collect([$request->user()->role])
            ->merge($request->user()->roles()->pluck('slug'))
            ->filter()
            ->map(fn ($role) => strtolower((string) $role));

        return $roles->contains(fn ($role) => str_contains($role, 'owner') || str_contains($role, 'admin'));
    }

    private function resultMessage(AttendanceLog $attendance, string $action): string
    {
        if ($attendance->review_status === 'pending') {
            return "Absen {$action} tercatat dan perlu ditinjau admin.";
        }
        if ($attendance->punctuality_status === 'late' && $action === 'masuk') {
            return "Absen masuk tercatat. Anda terlambat {$attendance->late_minutes} menit.";
        }
        if ($attendance->early_leave_minutes > 0 && $action === 'pulang') {
            return "Absen pulang tercatat {$attendance->early_leave_minutes} menit lebih awal.";
        }

        return "Absen {$action} berhasil dicatat.";
    }
}

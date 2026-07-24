<?php

namespace App\Domains\Employee\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Employee\Models\AttendanceAudit;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\EmployeeSchedule;
use App\Domains\Employee\Services\AttendanceService;
use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

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
            ->with(['outlet', 'schedule'])
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
            'Jadwal masuk',
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
                $record->scheduled_start_at?->toIso8601String(),
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

    public function schedules(Request $request)
    {
        $validated = $request->validate([
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'employee_id' => 'nullable|integer|exists:employees,id',
        ]);
        [$dateFrom, $dateTo] = $this->reportDates($validated);

        return EmployeeSchedule::with(['employee', 'outlet'])
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

        $schedule = EmployeeSchedule::create([
            ...$validated,
            'created_by' => $request->user()->id,
        ]);

        return response()->json($schedule->load(['employee', 'outlet']), 201);
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
        $schedule->update($validated);

        return response()->json($schedule->fresh()->load(['employee', 'outlet']));
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
                $deadline = CarbonImmutable::instance($attendance->scheduled_start_at)->addMinutes(
                    $attendance->outlet?->attendancePolicy?->late_tolerance_minutes ?? 0,
                );
                $lateMinutes = max(0, intdiv($checkIn->getTimestamp() - $deadline->getTimestamp(), 60));
                $changes += [
                    'late_minutes' => $lateMinutes,
                    'punctuality_status' => $lateMinutes > 0 ? 'late' : 'on_time',
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

        return response()->json($attendance->fresh()->load(['employee', 'outlet', 'reviewer', 'audits.actor']));
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
            'end_at' => [$required, 'date', 'after:start_at'],
            'shift_name' => [$required, 'string', 'max:100'],
            'status' => [$required, Rule::in(['scheduled', 'leave', 'sick', 'off', 'cancelled'])],
            'notes' => 'nullable|string|max:2000',
        ];
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
        return AttendanceLog::with(['employee', 'outlet', 'schedule', 'reviewer'])
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

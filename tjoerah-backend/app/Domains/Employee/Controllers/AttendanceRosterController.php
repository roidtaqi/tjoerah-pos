<?php

namespace App\Domains\Employee\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendanceShift;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\EmployeeSchedule;
use App\Domains\Employee\Models\EmployeeScheduleAudit;
use App\Domains\Employee\Models\ShiftChangeRequest;
use App\Domains\Employee\Services\AttendanceService;
use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AttendanceRosterController extends Controller
{
    public function __construct(private readonly AttendanceService $attendanceService) {}

    public function bulkUpsert(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'publication_status' => ['nullable', Rule::in(['draft', 'published'])],
            'change_reason' => 'nullable|string|max:2000',
            'assignments' => 'required|array|min:1|max:1000',
            'assignments.*.employee_id' => 'required|integer|exists:employees,id',
            'assignments.*.work_date' => 'required|date',
            'assignments.*.attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'assignments.*.status' => ['required', Rule::in(['scheduled', 'leave', 'sick', 'off', 'cancelled'])],
            'assignments.*.custom_start_time' => 'nullable|date_format:H:i',
            'assignments.*.custom_late_after_time' => 'nullable|date_format:H:i',
            'assignments.*.custom_end_time' => 'nullable|date_format:H:i',
            'assignments.*.notes' => 'nullable|string|max:2000',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $publicationStatus = $validated['publication_status'] ?? 'draft';
        $reason = trim($validated['change_reason'] ?? '') ?: null;

        $seen = [];
        foreach ($validated['assignments'] as $assignment) {
            $key = $assignment['employee_id'].':'.CarbonImmutable::parse($assignment['work_date'])->toDateString();
            if (isset($seen[$key])) {
                throw ValidationException::withMessages([
                    'assignments' => 'Karyawan yang sama hanya boleh memiliki satu jadwal per tanggal.',
                ]);
            }
            $seen[$key] = true;
        }

        $schedules = DB::transaction(function () use (
            $request,
            $validated,
            $outlet,
            $publicationStatus,
            $reason,
        ) {
            return collect($validated['assignments'])
                ->map(fn (array $assignment) => $this->upsertSchedule(
                    $request->user(),
                    $outlet,
                    $assignment,
                    $publicationStatus,
                    $reason,
                ));
        });

        return response()->json([
            'message' => $publicationStatus === 'published'
                ? 'Jadwal berhasil disimpan dan diterbitkan.'
                : 'Roster berhasil disimpan. Jadwal baru tetap draft hingga diterbitkan.',
            'updated_schedules' => $schedules->count(),
            'schedules' => $schedules->map->load(['employee', 'attendanceShift']),
        ]);
    }

    public function publish(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'date_from' => 'required|date',
            'date_to' => 'required|date|after_or_equal:date_from',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        [$dateFrom, $dateTo] = $this->dateRange(
            $validated['date_from'],
            $validated['date_to'],
        );
        $dateToExclusive = CarbonImmutable::parse($dateTo)->addDay()->toDateString();

        $count = DB::transaction(function () use ($request, $outlet, $dateFrom, $dateToExclusive) {
            $schedules = EmployeeSchedule::where('outlet_id', $outlet->id)
                ->where('work_date', '>=', $dateFrom)
                ->where('work_date', '<', $dateToExclusive)
                ->where('publication_status', 'draft')
                ->lockForUpdate()
                ->get();
            foreach ($schedules as $schedule) {
                $before = $this->snapshot($schedule);
                $schedule->update([
                    'publication_status' => 'published',
                    'published_at' => now(),
                    'published_by' => $request->user()->id,
                    'revision' => $schedule->revision + 1,
                ]);
                $this->audit($schedule, $request->user(), 'published', $before, 'Roster diterbitkan.');
            }

            return $schedules->count();
        });

        return response()->json([
            'message' => $count > 0
                ? "{$count} jadwal berhasil diterbitkan."
                : 'Seluruh jadwal pada periode ini sudah diterbitkan.',
            'published_schedules' => $count,
        ]);
    }

    public function copy(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'source_start_date' => 'required|date',
            'target_start_date' => 'required|date',
            'days' => 'required|integer|min:1|max:31',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $sourceStart = CarbonImmutable::parse($validated['source_start_date'])->startOfDay();
        $targetStart = CarbonImmutable::parse($validated['target_start_date'])->startOfDay();
        abort_if($sourceStart->equalTo($targetStart), 422, 'Periode sumber dan tujuan harus berbeda.');
        $days = (int) $validated['days'];
        $sourceEnd = $sourceStart->addDays($days - 1);
        $sourceEndExclusive = $sourceEnd->addDay();
        $policy = $this->attendanceService->policyForOutlet($outlet);
        $source = EmployeeSchedule::where('outlet_id', $outlet->id)
            ->where('publication_status', 'published')
            ->where('work_date', '>=', $sourceStart->toDateString())
            ->where('work_date', '<', $sourceEndExclusive->toDateString())
            ->get();
        abort_if($source->isEmpty(), 422, 'Tidak ada jadwal terbit pada periode sumber.');

        $schedules = DB::transaction(function () use (
            $request,
            $outlet,
            $source,
            $sourceStart,
            $targetStart,
            $policy,
        ) {
            return $source->map(function (EmployeeSchedule $schedule) use (
                $request,
                $outlet,
                $sourceStart,
                $targetStart,
                $policy,
            ) {
                $offset = $sourceStart->diffInDays($schedule->work_date, false);
                $targetDate = $targetStart->addDays($offset)->toDateString();
                $assignment = [
                    'employee_id' => $schedule->employee_id,
                    'work_date' => $targetDate,
                    'attendance_shift_id' => $schedule->attendance_shift_id,
                    'status' => $schedule->status,
                    'notes' => $schedule->notes,
                ];
                if ($schedule->is_custom_time && $schedule->status === 'scheduled') {
                    $assignment += [
                        'custom_start_time' => $schedule->start_at->setTimezone($policy->timezone)->format('H:i'),
                        'custom_late_after_time' => $schedule->late_after_at?->setTimezone($policy->timezone)->format('H:i'),
                        'custom_end_time' => $schedule->end_at->setTimezone($policy->timezone)->format('H:i'),
                    ];
                }

                return $this->upsertSchedule(
                    $request->user(),
                    $outlet,
                    $assignment,
                    'draft',
                    'Disalin dari roster periode sebelumnya.',
                    'copied',
                );
            });
        });

        return response()->json([
            'message' => $schedules->count().' jadwal disalin sebagai draft.',
            'copied_schedules' => $schedules->count(),
        ]);
    }

    public function mySchedule(Request $request)
    {
        $validated = $request->validate([
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
        ]);
        $employee = $this->selfEmployee($request);
        $dateFrom = CarbonImmutable::parse($validated['date_from'] ?? now()->toDateString());
        $dateTo = CarbonImmutable::parse($validated['date_to'] ?? $dateFrom->addDays(30));
        $dateToExclusive = $dateTo->addDay();
        abort_if($dateFrom->diffInDays($dateTo) > 62, 422, 'Rentang jadwal maksimal 63 hari.');

        return response()->json(EmployeeSchedule::with('attendanceShift')
            ->where('employee_id', $employee->id)
            ->where('publication_status', 'published')
            ->where('work_date', '>=', $dateFrom->toDateString())
            ->where('work_date', '<', $dateToExclusive->toDateString())
            ->orderBy('work_date')
            ->get());
    }

    public function myRequests(Request $request)
    {
        $employee = $this->selfEmployee($request);

        return response()->json(ShiftChangeRequest::with([
            'schedule.attendanceShift',
            'requestedAttendanceShift',
            'reviewer',
            'resultingSchedule.attendanceShift',
        ])->where('employee_id', $employee->id)
            ->latest()
            ->limit(50)
            ->get());
    }

    public function storeRequest(Request $request)
    {
        $validated = $request->validate($this->changeRequestRules());
        $employee = $this->selfEmployee($request);
        $workDate = CarbonImmutable::parse($validated['requested_work_date'])->toDateString();
        if (CarbonImmutable::parse($workDate)->lt(CarbonImmutable::today($employee->outlet?->timezone ?? 'Asia/Makassar'))) {
            throw ValidationException::withMessages([
                'requested_work_date' => 'Perubahan hanya dapat diminta untuk hari ini atau tanggal mendatang.',
            ]);
        }
        $this->validateRequestedAssignment($validated, $employee->outlet_id);
        abort_if(
            ShiftChangeRequest::where('employee_id', $employee->id)
                ->whereDate('requested_work_date', $workDate)
                ->where('status', 'pending')
                ->exists(),
            422,
            'Masih ada permintaan yang menunggu untuk tanggal tersebut.',
        );
        $schedule = EmployeeSchedule::where('employee_id', $employee->id)
            ->whereDate('work_date', $workDate)
            ->where('publication_status', 'published')
            ->first();

        $changeRequest = ShiftChangeRequest::create([
            ...$validated,
            'employee_id' => $employee->id,
            'outlet_id' => $employee->outlet_id,
            'employee_schedule_id' => $schedule?->id,
            'status' => 'pending',
        ]);

        return response()->json([
            'message' => 'Permintaan perubahan jadwal berhasil dikirim.',
            'request' => $changeRequest->load(['schedule.attendanceShift', 'requestedAttendanceShift']),
        ], 201);
    }

    public function cancelRequest(Request $request, ShiftChangeRequest $changeRequest)
    {
        $employee = $this->selfEmployee($request);
        abort_if($changeRequest->employee_id !== $employee->id, 404);
        abort_unless($changeRequest->status === 'pending', 422, 'Hanya permintaan yang menunggu yang dapat dibatalkan.');
        $changeRequest->update(['status' => 'cancelled']);

        return response()->json([
            'message' => 'Permintaan perubahan jadwal dibatalkan.',
            'request' => $changeRequest->fresh(),
        ]);
    }

    public function adminRequests(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'status' => ['nullable', Rule::in(['all', 'pending', 'approved', 'rejected', 'cancelled'])],
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);

        return response()->json(ShiftChangeRequest::with([
            'employee',
            'schedule.attendanceShift',
            'requestedAttendanceShift',
            'reviewer',
            'resultingSchedule.attendanceShift',
        ])->where('outlet_id', $outlet->id)
            ->when(
                ($validated['status'] ?? 'pending') !== 'all',
                fn ($query) => $query->where('status', $validated['status'] ?? 'pending'),
            )
            ->orderByRaw("CASE WHEN status = 'pending' THEN 0 ELSE 1 END")
            ->latest()
            ->limit(100)
            ->get());
    }

    public function reviewRequest(Request $request, ShiftChangeRequest $changeRequest)
    {
        $outlet = $this->accessibleOutlet($request, $changeRequest->outlet_id);
        abort_unless($changeRequest->status === 'pending', 422, 'Permintaan ini sudah diproses.');
        $validated = $request->validate([
            'decision' => ['required', Rule::in(['approved', 'rejected'])],
            'response_notes' => 'nullable|string|max:2000',
            'attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'status' => ['nullable', Rule::in(['scheduled', 'leave', 'sick', 'off', 'cancelled'])],
            'custom_start_time' => 'nullable|date_format:H:i',
            'custom_late_after_time' => 'nullable|date_format:H:i',
            'custom_end_time' => 'nullable|date_format:H:i',
        ]);
        if ($validated['decision'] === 'rejected') {
            $changeRequest->update([
                'status' => 'rejected',
                'response_notes' => trim($validated['response_notes'] ?? '') ?: null,
                'reviewed_by' => $request->user()->id,
                'reviewed_at' => now(),
            ]);

            return response()->json([
                'message' => 'Permintaan perubahan jadwal ditolak.',
                'request' => $changeRequest->fresh()->load(['employee', 'requestedAttendanceShift', 'reviewer']),
            ]);
        }

        $approvedStatus = $validated['status'] ?? $changeRequest->requested_status;
        $hasCustomOverride = filled($validated['custom_start_time'] ?? null)
            || filled($validated['custom_late_after_time'] ?? null)
            || filled($validated['custom_end_time'] ?? null);
        $approvedShiftId = array_key_exists('attendance_shift_id', $validated)
            ? $validated['attendance_shift_id']
            : ($hasCustomOverride ? null : $changeRequest->requested_attendance_shift_id);
        $assignment = [
            'employee_id' => $changeRequest->employee_id,
            'work_date' => $changeRequest->requested_work_date->toDateString(),
            'attendance_shift_id' => $approvedStatus === 'scheduled'
                ? $approvedShiftId
                : null,
            'status' => $approvedStatus,
            'custom_start_time' => $validated['custom_start_time']
                ?? $changeRequest->requested_start_time,
            'custom_late_after_time' => $validated['custom_late_after_time']
                ?? $changeRequest->requested_late_after_time,
            'custom_end_time' => $validated['custom_end_time']
                ?? $changeRequest->requested_end_time,
            'notes' => $validated['response_notes'] ?? null,
        ];
        $this->validateRequestedAssignment([
            'requested_status' => $assignment['status'],
            'requested_attendance_shift_id' => $assignment['attendance_shift_id'],
            'requested_start_time' => $assignment['custom_start_time'],
            'requested_late_after_time' => $assignment['custom_late_after_time'],
            'requested_end_time' => $assignment['custom_end_time'],
        ], $outlet->id);

        $schedule = DB::transaction(function () use ($request, $outlet, $assignment, $validated, $changeRequest) {
            $schedule = $this->upsertSchedule(
                $request->user(),
                $outlet,
                $assignment,
                'published',
                trim($validated['response_notes'] ?? '') ?: 'Disetujui dari permintaan perubahan jadwal.',
                'request_approved',
            );
            $changeRequest->update([
                'status' => 'approved',
                'response_notes' => trim($validated['response_notes'] ?? '') ?: null,
                'reviewed_by' => $request->user()->id,
                'reviewed_at' => now(),
                'resulting_schedule_id' => $schedule->id,
            ]);

            return $schedule;
        });

        return response()->json([
            'message' => 'Permintaan disetujui dan jadwal karyawan diperbarui.',
            'request' => $changeRequest->fresh()->load(['employee', 'requestedAttendanceShift', 'reviewer']),
            'schedule' => $schedule->load(['employee', 'attendanceShift']),
        ]);
    }

    public function audits(Request $request, EmployeeSchedule $schedule)
    {
        $this->accessibleOutlet($request, $schedule->outlet_id);

        return response()->json($schedule->audits()->with('actor')->get());
    }

    private function upsertSchedule(
        User $actor,
        Outlet $outlet,
        array $assignment,
        string $publicationStatus,
        ?string $reason,
        string $action = 'updated',
    ): EmployeeSchedule {
        $employee = Employee::whereKey((int) $assignment['employee_id'])
            ->where('outlet_id', $outlet->id)
            ->where('company_id', $outlet->company_id)
            ->firstOrFail();
        $workDate = CarbonImmutable::parse($assignment['work_date'])->toDateString();
        $status = $assignment['status'];
        $policy = $this->attendanceService->policyForOutlet($outlet);
        $shift = null;
        $isCustom = false;

        if ($status === 'scheduled' && ! empty($assignment['attendance_shift_id'])) {
            $shift = AttendanceShift::whereKey((int) $assignment['attendance_shift_id'])
                ->where('outlet_id', $outlet->id)
                ->where('is_active', true)
                ->firstOrFail();
            $window = $this->attendanceService->shiftWindowForDate($shift, $workDate, $policy->timezone);
        } elseif ($status === 'scheduled') {
            $window = $this->customWindow($assignment, $workDate, $policy->timezone);
            $isCustom = true;
        } else {
            $start = CarbonImmutable::parse("{$workDate} {$policy->work_start_time}", $policy->timezone);
            $end = CarbonImmutable::parse("{$workDate} {$policy->work_end_time}", $policy->timezone);
            if ($end->lessThanOrEqualTo($start)) {
                $end = $end->addDay();
            }
            $window = [
                'start' => $start->utc(),
                'late_after' => $start->addMinutes($policy->late_tolerance_minutes)->utc(),
                'end' => $end->utc(),
            ];
        }

        $schedule = EmployeeSchedule::where('employee_id', $employee->id)
            ->whereDate('work_date', $workDate)
            ->lockForUpdate()
            ->first();
        if ($schedule?->attendance()->exists()) {
            throw ValidationException::withMessages([
                'assignments' => "Jadwal {$employee->name} pada {$workDate} sudah memiliki absensi dan dikunci.",
            ]);
        }
        $before = $schedule ? $this->snapshot($schedule) : null;
        $effectivePublication = $schedule?->publication_status === 'published'
            ? 'published'
            : $publicationStatus;
        $data = [
            'employee_id' => $employee->id,
            'outlet_id' => $outlet->id,
            'attendance_shift_id' => $shift?->id,
            'work_date' => $workDate,
            'start_at' => $window['start'],
            'late_after_at' => $window['late_after'],
            'end_at' => $window['end'],
            'shift_name' => $status === 'scheduled'
                ? ($shift?->name ?? 'Jam khusus')
                : $this->statusLabel($status),
            'status' => $status,
            'publication_status' => $effectivePublication,
            'published_at' => $effectivePublication === 'published'
                ? ($schedule?->published_at ?? now())
                : null,
            'published_by' => $effectivePublication === 'published'
                ? ($schedule?->published_by ?? $actor->id)
                : null,
            'is_custom_time' => $isCustom,
            'notes' => trim($assignment['notes'] ?? '') ?: null,
            'change_reason' => $reason,
            'created_by' => $schedule?->created_by ?? $actor->id,
            'revision' => $schedule ? $schedule->revision + 1 : 1,
        ];
        if ($schedule) {
            $schedule->update($data);
        } else {
            $schedule = EmployeeSchedule::create($data);
            $action = $action === 'updated' ? 'created' : $action;
        }
        $this->audit($schedule, $actor, $action, $before, $reason);

        return $schedule->fresh();
    }

    private function customWindow(array $assignment, string $workDate, string $timezone): array
    {
        foreach (['custom_start_time', 'custom_late_after_time', 'custom_end_time'] as $field) {
            if (empty($assignment[$field])) {
                throw ValidationException::withMessages([
                    $field => 'Jam mulai, batas terlambat, dan jam selesai wajib diisi untuk jam khusus.',
                ]);
            }
        }
        $start = CarbonImmutable::parse("{$workDate} {$assignment['custom_start_time']}", $timezone);
        $lateAfter = CarbonImmutable::parse("{$workDate} {$assignment['custom_late_after_time']}", $timezone);
        $end = CarbonImmutable::parse("{$workDate} {$assignment['custom_end_time']}", $timezone);
        if ($end->lessThanOrEqualTo($start)) {
            $end = $end->addDay();
        }
        if ($lateAfter->lessThan($start)) {
            $lateAfter = $lateAfter->addDay();
        }
        if ($lateAfter->greaterThan($end)) {
            throw ValidationException::withMessages([
                'custom_late_after_time' => 'Batas terlambat harus berada di antara jam mulai dan selesai.',
            ]);
        }

        return [
            'start' => $start->utc(),
            'late_after' => $lateAfter->utc(),
            'end' => $end->utc(),
        ];
    }

    private function changeRequestRules(): array
    {
        return [
            'requested_work_date' => 'required|date',
            'requested_attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'requested_status' => ['required', Rule::in(['scheduled', 'leave', 'off'])],
            'requested_start_time' => 'nullable|date_format:H:i',
            'requested_late_after_time' => 'nullable|date_format:H:i',
            'requested_end_time' => 'nullable|date_format:H:i',
            'reason' => 'required|string|min:5|max:2000',
        ];
    }

    private function validateRequestedAssignment(array $data, int $outletId): void
    {
        $status = $data['requested_status'];
        $shiftId = $data['requested_attendance_shift_id'] ?? null;
        if ($shiftId) {
            abort_unless(
                AttendanceShift::whereKey((int) $shiftId)->where('outlet_id', $outletId)->where('is_active', true)->exists(),
                422,
                'Shift yang dipilih tidak tersedia pada outlet karyawan.',
            );
        }
        if ($status === 'scheduled' && ! $shiftId) {
            foreach (['requested_start_time', 'requested_late_after_time', 'requested_end_time'] as $field) {
                if (empty($data[$field])) {
                    throw ValidationException::withMessages([
                        $field => 'Pilih shift atau lengkapi jam kerja khusus.',
                    ]);
                }
            }
        }
    }

    private function snapshot(EmployeeSchedule $schedule): array
    {
        return $schedule->only([
            'employee_id',
            'outlet_id',
            'attendance_shift_id',
            'work_date',
            'start_at',
            'late_after_at',
            'end_at',
            'shift_name',
            'status',
            'publication_status',
            'is_custom_time',
            'notes',
            'change_reason',
            'revision',
        ]);
    }

    private function audit(
        EmployeeSchedule $schedule,
        User $actor,
        string $action,
        ?array $before,
        ?string $reason,
    ): void {
        EmployeeScheduleAudit::create([
            'employee_schedule_id' => $schedule->id,
            'employee_id' => $schedule->employee_id,
            'actor_id' => $actor->id,
            'action' => $action,
            'before' => $before,
            'after' => $this->snapshot($schedule->fresh()),
            'reason' => $reason,
        ]);
    }

    private function statusLabel(string $status): string
    {
        return match ($status) {
            'off' => 'Off',
            'leave' => 'Cuti',
            'sick' => 'Sakit',
            'cancelled' => 'Dibatalkan',
            default => 'Jadwal',
        };
    }

    private function dateRange(string $from, string $to): array
    {
        $dateFrom = CarbonImmutable::parse($from)->startOfDay();
        $dateTo = CarbonImmutable::parse($to)->startOfDay();
        abort_if($dateFrom->diffInDays($dateTo) > 30, 422, 'Periode roster maksimal 31 hari.');

        return [$dateFrom->toDateString(), $dateTo->toDateString()];
    }

    private function selfEmployee(Request $request): Employee
    {
        $employee = Employee::with('outlet')
            ->where('user_id', $request->user()->id)
            ->where('is_active', true)
            ->first();
        abort_if(! $employee, 422, 'Akun belum terhubung dengan profil karyawan aktif.');

        return $employee;
    }

    private function accessibleOutlet(Request $request, int $outletId): Outlet
    {
        return Outlet::query()
            ->where('is_active', true)
            ->when(
                $request->user()->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->whereHas(
                    'users',
                    fn ($users) => $users->whereKey($request->user()->id),
                ),
            )
            ->findOrFail($outletId);
    }
}

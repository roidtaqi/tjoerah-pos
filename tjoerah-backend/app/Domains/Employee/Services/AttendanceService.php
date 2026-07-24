<?php

namespace App\Domains\Employee\Services;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\EmployeeSchedule;
use Carbon\CarbonImmutable;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

class AttendanceService
{
    public function context(User $user, ?int $requestedOutletId = null): array
    {
        $employee = $this->resolveEmployee($user, $requestedOutletId);
        $outlet = $employee->outlet;
        $policy = $this->policyForOutlet($outlet);
        [$schedule, $scheduledStart, $scheduledEnd] = $this->scheduleWindow($employee, $policy);
        $activeAttendance = $employee->attendanceLogs()
            ->whereNull('check_out_at')
            ->latest('check_in_at')
            ->first();

        return [
            'employee' => $employee->load('outlet'),
            'outlet' => $outlet,
            'policy' => $policy,
            'schedule' => $schedule,
            'scheduled_start_at' => $scheduledStart,
            'scheduled_end_at' => $scheduledEnd,
            'active_attendance' => $activeAttendance,
            'recent_attendance' => $employee->attendanceLogs()
                ->latest('check_in_at')
                ->limit(10)
                ->get(),
            'server_time' => now()->utc(),
        ];
    }

    public function checkIn(
        User $user,
        array $data,
        ?UploadedFile $photo,
    ): AttendanceLog {
        if (! empty($data['request_id'])) {
            $existing = AttendanceLog::where('check_in_request_id', $data['request_id'])
                ->whereHas('employee', fn ($employee) => $employee->where('user_id', $user->id))
                ->first();
            if ($existing) {
                return $existing->load(['employee', 'outlet', 'schedule']);
            }
        }

        $employee = $this->resolveEmployee($user, isset($data['outlet_id']) ? (int) $data['outlet_id'] : null);
        $outlet = $employee->outlet;
        $policy = $this->policyForOutlet($outlet);
        $this->ensurePolicyIsActive($policy);

        if ($policy->require_check_in_photo && ! $photo) {
            throw ValidationException::withMessages([
                'photo' => 'Foto selfie wajib diambil saat absen masuk.',
            ]);
        }

        $openAttendance = $employee->attendanceLogs()
            ->whereNull('check_out_at')
            ->latest('check_in_at')
            ->first();
        if ($openAttendance) {
            throw ValidationException::withMessages([
                'attendance' => 'Anda sudah melakukan absen masuk dan belum melakukan absen pulang.',
            ]);
        }

        [$schedule, $scheduledStart, $scheduledEnd] = $this->scheduleWindow($employee, $policy);
        if ($schedule && $schedule->status !== 'scheduled') {
            $label = match ($schedule->status) {
                'leave' => 'cuti',
                'sick' => 'sakit',
                'off' => 'libur',
                'cancelled' => 'dibatalkan',
                default => $schedule->status,
            };
            throw ValidationException::withMessages([
                'attendance' => "Anda tidak dijadwalkan masuk karena status hari ini: {$label}.",
            ]);
        }
        $now = CarbonImmutable::now('UTC');
        $checkInOpensAt = $scheduledStart->subMinutes($policy->check_in_open_minutes);
        if ($now->isBefore($checkInOpensAt)) {
            throw ValidationException::withMessages([
                'attendance' => 'Absen masuk dibuka pada '.$checkInOpensAt->setTimezone($policy->timezone)->format('H:i').'.',
            ]);
        }

        $assessment = $this->assessLocation($policy, $data);
        $this->validateOutsideReason($policy, $assessment['outside'], $data['outside_reason'] ?? null);

        $deadline = $scheduledStart->addMinutes($policy->late_tolerance_minutes);
        $lateMinutes = max(0, intdiv($now->getTimestamp() - $deadline->getTimestamp(), 60));
        $punctuality = $lateMinutes > 0 ? 'late' : 'on_time';
        $reviewStatus = $assessment['flags'] === [] ? 'approved' : 'pending';
        $photoData = $this->storePhoto($photo, $employee, 'check-in', $now);

        try {
            $attendance = DB::transaction(fn () => AttendanceLog::create([
                'employee_id' => $employee->id,
                'outlet_id' => $outlet->id,
                'work_date' => $scheduledStart->setTimezone($policy->timezone)->toDateString(),
                'employee_schedule_id' => $schedule?->id,
                'scheduled_start_at' => $scheduledStart,
                'scheduled_end_at' => $scheduledEnd,
                'check_in_at' => $now,
                'punctuality_status' => $punctuality,
                'late_minutes' => $lateMinutes,
                'review_status' => $reviewStatus,
                'source' => $data['source'] ?? 'mobile',
                'notes' => $data['notes'] ?? null,
                'check_in_photo_path' => $photoData['path'],
                'check_in_photo_hash' => $photoData['hash'],
                'check_in_latitude' => $data['latitude'],
                'check_in_longitude' => $data['longitude'],
                'check_in_accuracy_meters' => $data['accuracy_meters'],
                'check_in_distance_meters' => $assessment['distance'],
                'check_in_is_mock' => (bool) ($data['is_mock'] ?? false),
                'check_in_outside_geofence' => $assessment['outside'],
                'check_in_outside_reason' => $data['outside_reason'] ?? null,
                'check_in_device_at' => $data['device_captured_at'] ?? null,
                'device_id' => $data['device_id'] ?? null,
                'check_in_request_id' => $data['request_id'] ?? (string) Str::uuid(),
                'anomaly_flags' => $assessment['flags'],
            ]));
        } catch (Throwable $error) {
            if ($photoData['path']) {
                Storage::disk('local')->delete($photoData['path']);
            }
            throw $error;
        }

        return $attendance->load(['employee', 'outlet', 'schedule']);
    }

    public function checkOut(
        User $user,
        array $data,
        ?UploadedFile $photo,
    ): AttendanceLog {
        if (! empty($data['request_id'])) {
            $existing = AttendanceLog::where('check_out_request_id', $data['request_id'])
                ->whereHas('employee', fn ($employee) => $employee->where('user_id', $user->id))
                ->first();
            if ($existing) {
                return $existing->load(['employee', 'outlet', 'schedule']);
            }
        }

        $employee = $this->resolveEmployee($user, isset($data['outlet_id']) ? (int) $data['outlet_id'] : null);
        $attendance = $employee->attendanceLogs()
            ->when(
                $data['attendance_log_id'] ?? null,
                fn ($query, $attendanceId) => $query->whereKey($attendanceId),
            )
            ->whereNull('check_out_at')
            ->latest('check_in_at')
            ->firstOrFail();
        $policy = $this->policyForOutlet($employee->outlet);
        $this->ensurePolicyIsActive($policy);

        if ($policy->require_check_out_photo && ! $photo) {
            throw ValidationException::withMessages([
                'photo' => 'Foto selfie wajib diambil saat absen pulang.',
            ]);
        }

        $assessment = $this->assessLocation($policy, $data);
        $this->validateOutsideReason($policy, $assessment['outside'], $data['outside_reason'] ?? null);

        $now = CarbonImmutable::now('UTC');
        $earlyLeaveMinutes = $attendance->scheduled_end_at
            ? max(
                0,
                intdiv(
                    CarbonImmutable::instance($attendance->scheduled_end_at)->utc()->getTimestamp()
                    - $now->getTimestamp(),
                    60,
                ),
            )
            : 0;
        $flags = array_values(array_unique([
            ...($attendance->anomaly_flags ?? []),
            ...array_map(fn (string $flag) => 'check_out_'.$flag, $assessment['flags']),
            ...($earlyLeaveMinutes > 0 ? ['early_leave'] : []),
        ]));
        $photoData = $this->storePhoto($photo, $employee, 'check-out', $now);

        try {
            DB::transaction(function () use (
                $attendance,
                $data,
                $assessment,
                $earlyLeaveMinutes,
                $flags,
                $photoData,
                $now,
            ): void {
                $attendance->update([
                    'check_out_at' => $now,
                    'early_leave_minutes' => $earlyLeaveMinutes,
                    'review_status' => $flags === [] ? $attendance->review_status : 'pending',
                    'notes' => $data['notes'] ?? $attendance->notes,
                    'check_out_photo_path' => $photoData['path'],
                    'check_out_photo_hash' => $photoData['hash'],
                    'check_out_latitude' => $data['latitude'],
                    'check_out_longitude' => $data['longitude'],
                    'check_out_accuracy_meters' => $data['accuracy_meters'],
                    'check_out_distance_meters' => $assessment['distance'],
                    'check_out_is_mock' => (bool) ($data['is_mock'] ?? false),
                    'check_out_outside_geofence' => $assessment['outside'],
                    'check_out_outside_reason' => $data['outside_reason'] ?? null,
                    'check_out_device_at' => $data['device_captured_at'] ?? null,
                    'check_out_request_id' => $data['request_id'] ?? (string) Str::uuid(),
                    'anomaly_flags' => $flags,
                ]);
            });
        } catch (Throwable $error) {
            if ($photoData['path']) {
                Storage::disk('local')->delete($photoData['path']);
            }
            throw $error;
        }

        return $attendance->fresh()->load(['employee', 'outlet', 'schedule']);
    }

    public function resolveEmployee(User $user, ?int $requestedOutletId = null): Employee
    {
        $employee = $user->employee;
        if ($employee) {
            if (! $employee->is_active) {
                throw ValidationException::withMessages([
                    'employee' => 'Profil karyawan tidak aktif.',
                ]);
            }

            if (! $employee->outlet_id) {
                $employee->update(['outlet_id' => $this->resolveOutlet($user, $requestedOutletId)->id]);
            }

            return $employee->fresh('outlet');
        }

        $outlet = $this->resolveOutlet($user, $requestedOutletId);

        return Employee::create([
            'company_id' => $user->company_id ?? $outlet->company_id,
            'outlet_id' => $outlet->id,
            'user_id' => $user->id,
            'employee_number' => 'USR-'.str_pad((string) $user->id, 4, '0', STR_PAD_LEFT),
            'name' => $user->name,
            'email' => $user->email,
            'position' => $user->role,
            'hire_date' => now()->toDateString(),
            'is_active' => true,
        ])->load('outlet');
    }

    public function policyForOutlet(Outlet $outlet): AttendancePolicy
    {
        return AttendancePolicy::firstOrCreate(
            ['outlet_id' => $outlet->id],
            [
                'company_id' => $outlet->company_id,
                'timezone' => $outlet->timezone ?: config('app.timezone', 'Asia/Makassar'),
            ],
        );
    }

    /**
     * @return array{0: ?EmployeeSchedule, 1: CarbonImmutable, 2: CarbonImmutable}
     */
    public function scheduleWindow(
        Employee $employee,
        AttendancePolicy $policy,
    ): array {
        $now = CarbonImmutable::now('UTC');
        $localDate = $now->setTimezone($policy->timezone)->toDateString();
        $schedule = EmployeeSchedule::where('employee_id', $employee->id)
            ->whereDate('work_date', $localDate)
            ->orderByRaw("CASE WHEN status = 'scheduled' THEN 0 ELSE 1 END")
            ->orderBy('start_at')
            ->first();

        if ($schedule) {
            return [
                $schedule,
                CarbonImmutable::instance($schedule->start_at)->utc(),
                CarbonImmutable::instance($schedule->end_at)->utc(),
            ];
        }

        $scheduledStart = CarbonImmutable::parse(
            $localDate.' '.$policy->work_start_time,
            $policy->timezone,
        )->utc();
        $scheduledEnd = CarbonImmutable::parse(
            $localDate.' '.$policy->work_end_time,
            $policy->timezone,
        )->utc();
        if ($scheduledEnd->lessThanOrEqualTo($scheduledStart)) {
            $scheduledEnd = $scheduledEnd->addDay();
        }

        return [null, $scheduledStart, $scheduledEnd];
    }

    private function resolveOutlet(User $user, ?int $requestedOutletId): Outlet
    {
        $query = Outlet::query()->where('is_active', true);
        if ($user->company_id) {
            $query->where('company_id', $user->company_id);
        } else {
            $query->whereHas('users', fn ($users) => $users->whereKey($user->id));
        }

        if ($requestedOutletId) {
            return $query->findOrFail($requestedOutletId);
        }

        $outlet = $user->outlets()->where('is_active', true)->first()
            ?? $query->first();

        if (! $outlet) {
            throw ValidationException::withMessages([
                'outlet' => 'Belum ada outlet aktif yang terhubung dengan akun ini.',
            ]);
        }

        return $outlet;
    }

    /**
     * @return array{distance: ?float, outside: bool, flags: array<int, string>}
     */
    private function assessLocation(AttendancePolicy $policy, array $data): array
    {
        $flags = [];
        $accuracy = (float) $data['accuracy_meters'];
        if ($accuracy > $policy->maximum_accuracy_meters) {
            $flags[] = 'low_accuracy';
        }
        if ((bool) ($data['is_mock'] ?? false)) {
            $flags[] = 'mock_location';
        }
        if (isset($data['device_captured_at'])) {
            $deviceTime = CarbonImmutable::parse($data['device_captured_at'])->utc();
            if (abs($deviceTime->diffInSeconds(CarbonImmutable::now('UTC'), false)) > 300) {
                $flags[] = 'clock_drift';
            }
        }

        $distance = null;
        $outside = false;
        if ($policy->latitude !== null && $policy->longitude !== null) {
            $distance = $this->distanceMeters(
                $policy->latitude,
                $policy->longitude,
                (float) $data['latitude'],
                (float) $data['longitude'],
            );
            $outside = $distance > $policy->geofence_radius_meters;
            if ($outside) {
                $flags[] = 'outside_geofence';
            }
        }

        return [
            'distance' => $distance === null ? null : round($distance, 2),
            'outside' => $outside,
            'flags' => $flags,
        ];
    }

    private function validateOutsideReason(
        AttendancePolicy $policy,
        bool $outside,
        ?string $reason,
    ): void {
        if (! $outside) {
            return;
        }
        if (! $policy->allow_outside_with_reason) {
            throw ValidationException::withMessages([
                'location' => 'Anda berada di luar area absensi outlet.',
            ]);
        }
        if (blank($reason)) {
            throw ValidationException::withMessages([
                'outside_reason' => 'Berikan alasan karena Anda berada di luar area outlet.',
            ]);
        }
    }

    /**
     * @return array{path: ?string, hash: ?string}
     */
    private function storePhoto(
        ?UploadedFile $photo,
        Employee $employee,
        string $type,
        CarbonImmutable $capturedAt,
    ): array {
        if (! $photo) {
            return ['path' => null, 'hash' => null];
        }

        $directory = sprintf(
            'attendance/%s/%s',
            $employee->uuid ?: $employee->id,
            $capturedAt->format('Y/m'),
        );
        $filename = sprintf('%s-%s.jpg', $type, Str::uuid());
        $path = $photo->storeAs($directory, $filename, 'local');

        if (! $path) {
            throw ValidationException::withMessages([
                'photo' => 'Foto absensi belum dapat disimpan.',
            ]);
        }

        return [
            'path' => $path,
            'hash' => hash_file('sha256', Storage::disk('local')->path($path)),
        ];
    }

    private function ensurePolicyIsActive(AttendancePolicy $policy): void
    {
        if (! $policy->is_active) {
            throw ValidationException::withMessages([
                'attendance' => 'Absensi sedang dinonaktifkan untuk outlet ini.',
            ]);
        }
    }

    private function distanceMeters(
        float $fromLatitude,
        float $fromLongitude,
        float $toLatitude,
        float $toLongitude,
    ): float {
        $earthRadius = 6371000;
        $latitudeDelta = deg2rad($toLatitude - $fromLatitude);
        $longitudeDelta = deg2rad($toLongitude - $fromLongitude);
        $a = sin($latitudeDelta / 2) ** 2
            + cos(deg2rad($fromLatitude))
            * cos(deg2rad($toLatitude))
            * sin($longitudeDelta / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}

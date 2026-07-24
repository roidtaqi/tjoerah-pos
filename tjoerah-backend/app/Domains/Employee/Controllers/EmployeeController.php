<?php

namespace App\Domains\Employee\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\AttendanceShift;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\Shift;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class EmployeeController extends Controller
{
    public function index(Request $request)
    {
        return Employee::with(['user', 'outlet', 'attendanceShift'])
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->whereIn('outlet_id', $this->assignedOutletIds($request)),
            )
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->orderBy('name')
            ->paginate(100);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'user_id' => 'nullable|integer|exists:users,id',
            'employee_number' => 'nullable|string|max:100',
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'position' => 'nullable|string|max:100',
            'hire_date' => 'nullable|date',
            'is_active' => 'boolean',
        ]);
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        if (isset($validated['outlet_id'])) {
            $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
            $validated['company_id'] = $request->user()?->company_id ?? $outlet->company_id;
        }
        $this->ensureShiftMatchesOutlet(
            $validated['attendance_shift_id'] ?? null,
            $validated['outlet_id'] ?? null,
        );
        if (isset($validated['user_id'])) {
            $this->accessibleUser($request, (int) $validated['user_id']);
        }
        $employee = Employee::create($validated);

        return response()->json($employee->load(['user', 'outlet', 'attendanceShift']), 201);
    }

    public function update(Request $request, Employee $employee)
    {
        $this->ensureAccessible($request, $employee);
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'user_id' => 'nullable|integer|exists:users,id',
            'employee_number' => 'nullable|string|max:100',
            'name' => 'sometimes|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'position' => 'nullable|string|max:100',
            'hire_date' => 'nullable|date',
            'is_active' => 'boolean',
        ]);
        if (isset($validated['outlet_id'])) {
            $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        }
        $this->ensureShiftMatchesOutlet(
            $validated['attendance_shift_id'] ?? $employee->attendance_shift_id,
            $validated['outlet_id'] ?? $employee->outlet_id,
        );
        if (isset($validated['user_id'])) {
            $this->accessibleUser($request, (int) $validated['user_id']);
        }
        $employee->update($validated);

        return response()->json($employee->fresh()->load(['user', 'outlet', 'attendanceShift']));
    }

    public function destroy(Request $request, Employee $employee)
    {
        $this->ensureAccessible($request, $employee);
        abort_if($employee->attendanceLogs()->exists(), 422, 'Karyawan memiliki riwayat absensi dan hanya dapat dinonaktifkan.');
        $employee->delete();

        return response()->noContent();
    }

    public function checkIn(Request $request)
    {
        $attendance = AttendanceLog::create($request->validate([
            'employee_id' => 'required|integer|exists:employees,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'source' => 'nullable|string|max:50',
            'notes' => 'nullable|string',
        ]) + ['check_in_at' => now()]);

        return response()->json($attendance, 201);
    }

    public function checkOut(Request $request)
    {
        $validated = $request->validate([
            'attendance_log_id' => 'nullable|integer|exists:attendance_logs,id',
            'employee_id' => 'required_without:attendance_log_id|integer|exists:employees,id',
            'notes' => 'nullable|string',
        ]);

        $attendance = isset($validated['attendance_log_id'])
            ? AttendanceLog::findOrFail($validated['attendance_log_id'])
            : AttendanceLog::where('employee_id', $validated['employee_id'])->whereNull('check_out_at')->latest()->firstOrFail();

        $attendance->update([
            'check_out_at' => now(),
            'notes' => $validated['notes'] ?? $attendance->notes,
        ]);

        return response()->json($attendance);
    }

    public function startShift(Request $request)
    {
        $shift = Shift::create([
            ...$request->validate([
                'outlet_id' => 'required|integer|exists:outlets,id',
                'employee_id' => 'nullable|integer|exists:employees,id',
                'shift_number' => 'nullable|string|max:100',
                'opening_cash' => 'nullable|numeric',
            ]),
            'opened_by' => $request->user()?->id,
            'started_at' => now(),
            'status' => 'open',
        ]);

        return response()->json($shift, 201);
    }

    public function endShift(Request $request)
    {
        $validated = $request->validate([
            'shift_id' => 'required|integer|exists:shifts,id',
            'closing_cash' => 'nullable|numeric',
        ]);

        $shift = Shift::findOrFail($validated['shift_id']);
        $shift->update([
            'closed_by' => $request->user()?->id,
            'ended_at' => now(),
            'closing_cash' => $validated['closing_cash'] ?? null,
            'status' => 'closed',
        ]);

        return response()->json($shift);
    }

    private function ensureAccessible(Request $request, Employee $employee): void
    {
        abort_if(
            $request->user()?->company_id
                ? $employee->company_id !== $request->user()->company_id
                : ! in_array($employee->outlet_id, $this->assignedOutletIds($request), true),
            404,
        );
    }

    private function accessibleOutlet(Request $request, int $outletId): Outlet
    {
        return Outlet::query()
            ->when($request->user()?->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when(! $request->user()?->company_id, fn ($query) => $query->whereIn('id', $this->assignedOutletIds($request)))
            ->findOrFail($outletId);
    }

    private function accessibleUser(Request $request, int $userId): User
    {
        return User::query()
            ->when($request->user()?->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when(! $request->user()?->company_id, function ($query) use ($request) {
                $query->whereHas(
                    'outlets',
                    fn ($outlets) => $outlets->whereIn('outlets.id', $this->assignedOutletIds($request)),
                );
            })
            ->findOrFail($userId);
    }

    private function ensureShiftMatchesOutlet(?int $shiftId, ?int $outletId): void
    {
        if (! $shiftId) {
            return;
        }

        abort_unless(
            AttendanceShift::whereKey($shiftId)
                ->where('outlet_id', $outletId)
                ->exists(),
            422,
            'Shift absensi tidak terhubung dengan outlet karyawan.',
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
}

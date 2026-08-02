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
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class EmployeeController extends Controller
{
    public function index(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'role' => ['nullable', Rule::in(array_keys($this->roleOptions()))],
            'status' => ['nullable', Rule::in(['all', 'active', 'inactive'])],
            'q' => 'nullable|string|max:255',
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);

        return Employee::with(['user', 'outlet', 'attendanceShift'])
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->whereIn('outlet_id', $this->assignedOutletIds($request)),
            )
            ->when($validated['outlet_id'] ?? null, fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($validated['role'] ?? null, fn ($query, $role) => $query->whereHas('user', fn ($user) => $user->where('role', $role)))
            ->when(
                ($validated['status'] ?? 'all') !== 'all',
                fn ($query) => $query->where('is_active', $validated['status'] === 'active'),
            )
            ->when($validated['q'] ?? null, function ($query, $search) {
                $term = '%'.trim($search).'%';
                $query->where(function ($query) use ($term) {
                    $query->where('name', 'like', $term)
                        ->orWhere('employee_number', 'like', $term)
                        ->orWhere('email', 'like', $term)
                        ->orWhere('phone', 'like', $term);
                });
            })
            ->orderBy('name')
            ->paginate($request->integer('per_page', 100));
    }

    public function options(Request $request)
    {
        $outlets = Outlet::query()
            ->with(['attendanceShifts' => fn ($query) => $query
                ->where('is_active', true)
                ->orderBy('sort_order')])
            ->where('is_active', true)
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->whereIn('id', $this->assignedOutletIds($request)),
            )
            ->orderBy('name')
            ->get();
        $roles = collect($this->roleOptions())
            ->map(
                fn ($details, $role) => [
                    'value' => $role,
                    'assignable' => $role !== 'admin'
                        || $request->user()?->role === 'owner',
                    ...$details,
                ],
            )
            ->values();

        return response()->json([
            'roles' => $roles,
            'outlets' => $outlets,
            'employment_statuses' => [
                ['value' => 'permanent', 'label' => 'Tetap'],
                ['value' => 'contract', 'label' => 'Kontrak'],
                ['value' => 'part_time', 'label' => 'Paruh waktu'],
                ['value' => 'intern', 'label' => 'Magang'],
            ],
        ]);
    }

    public function store(Request $request)
    {
        $this->normalizeLoginFields($request);
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'user_id' => 'nullable|integer|exists:users,id',
            'employee_number' => [
                'required',
                'string',
                'max:100',
                Rule::unique('employees', 'employee_number')
                    ->where('company_id', $request->user()?->company_id),
            ],
            'name' => 'required|string|max:255',
            'phone' => [
                'nullable',
                'string',
                'max:50',
                'digits_between:8,15',
                Rule::unique('users', 'phone')->ignore($request->input('user_id')),
            ],
            'email' => [
                'required_without:user_id',
                'email',
                'max:255',
                Rule::unique('users', 'email')->ignore($request->input('user_id')),
            ],
            'username' => [
                'nullable',
                'string',
                'min:3',
                'max:100',
                'regex:/^[a-z][a-z0-9._-]*$/',
                Rule::unique('users', 'username')->ignore($request->input('user_id')),
            ],
            'password' => 'required_without:user_id|string|min:8|max:255',
            'pin' => ['required_without:user_id', 'digits_between:4,6'],
            'role' => ['required_without:user_id', Rule::in(array_keys($this->roleOptions()))],
            'position' => 'nullable|string|max:100',
            'employment_status' => ['required', Rule::in(['permanent', 'contract', 'part_time', 'intern'])],
            'hire_date' => 'nullable|date',
            'birth_date' => 'nullable|date|before:today',
            'gender' => ['nullable', Rule::in(['male', 'female', 'other'])],
            'identity_number' => 'nullable|string|max:100',
            'address' => 'nullable|string|max:2000',
            'emergency_contact_name' => 'nullable|string|max:255',
            'emergency_contact_phone' => 'nullable|string|max:50',
            'is_active' => 'boolean',
        ]);
        $this->ensureRoleCanBeAssigned($request, $validated['role'] ?? null);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $companyId = $request->user()?->company_id ?? $outlet->company_id;
        $this->ensureShiftMatchesOutlet(
            $validated['attendance_shift_id'] ?? null,
            $validated['outlet_id'] ?? null,
        );
        $employee = DB::transaction(function () use (
            $request,
            $validated,
            $companyId,
            $outlet,
        ) {
            if (isset($validated['user_id'])) {
                $user = $this->accessibleUser($request, (int) $validated['user_id']);
                $user->update(
                    collect($validated)
                        ->only(['name', 'username', 'email', 'phone', 'password', 'pin', 'role', 'is_active'])
                        ->reject(fn ($value, $key) => $key === 'password' && blank($value))
                        ->all(),
                );
            } else {
                $user = User::create([
                    'company_id' => $companyId,
                    'name' => $validated['name'],
                    'username' => $validated['username'] ?? null,
                    'email' => $validated['email'],
                    'phone' => $validated['phone'] ?? null,
                    'password' => $validated['password'],
                    'pin' => $validated['pin'],
                    'role' => $validated['role'],
                    'is_active' => $validated['is_active'] ?? true,
                ]);
            }
            $user->outlets()->syncWithoutDetaching([$outlet->id]);

            return Employee::create([
                ...$this->employeeData($validated),
                'company_id' => $companyId,
                'user_id' => $user->id,
            ]);
        });

        return response()->json(
            $employee->load(['user', 'outlet', 'attendanceShift']),
            201,
        );
    }

    public function update(Request $request, Employee $employee)
    {
        $this->ensureAccessible($request, $employee);
        $this->normalizeLoginFields($request);
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'attendance_shift_id' => 'nullable|integer|exists:attendance_shifts,id',
            'employee_number' => [
                'sometimes',
                'string',
                'max:100',
                Rule::unique('employees', 'employee_number')
                    ->where('company_id', $employee->company_id)
                    ->ignore($employee->id),
            ],
            'name' => 'sometimes|string|max:255',
            'phone' => [
                'nullable',
                'string',
                'max:50',
                'digits_between:8,15',
                Rule::unique('users', 'phone')->ignore($employee->user_id),
            ],
            'email' => [
                'sometimes',
                'email',
                'max:255',
                Rule::unique('users', 'email')->ignore($employee->user_id),
            ],
            'username' => [
                'sometimes',
                'nullable',
                'string',
                'min:3',
                'max:100',
                'regex:/^[a-z][a-z0-9._-]*$/',
                Rule::unique('users', 'username')->ignore($employee->user_id),
            ],
            'password' => 'nullable|string|min:8|max:255',
            'pin' => ['sometimes', 'digits_between:4,6'],
            'role' => ['sometimes', Rule::in(array_keys($this->roleOptions()))],
            'position' => 'nullable|string|max:100',
            'employment_status' => ['sometimes', Rule::in(['permanent', 'contract', 'part_time', 'intern'])],
            'hire_date' => 'nullable|date',
            'birth_date' => 'nullable|date|before:today',
            'gender' => ['nullable', Rule::in(['male', 'female', 'other'])],
            'identity_number' => 'nullable|string|max:100',
            'address' => 'nullable|string|max:2000',
            'emergency_contact_name' => 'nullable|string|max:255',
            'emergency_contact_phone' => 'nullable|string|max:50',
            'is_active' => 'boolean',
        ]);
        $this->ensureRoleCanBeAssigned(
            $request,
            $validated['role'] ?? null,
            $employee,
        );
        $outlet = null;
        if (isset($validated['outlet_id'])) {
            $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        }
        $this->ensureShiftMatchesOutlet(
            $validated['attendance_shift_id'] ?? $employee->attendance_shift_id,
            $validated['outlet_id'] ?? $employee->outlet_id,
        );
        DB::transaction(function () use ($validated, $employee, $outlet): void {
            $employee->update($this->employeeData($validated));
            if ($employee->user) {
                $userData = collect($validated)
                    ->only(['name', 'username', 'email', 'phone', 'password', 'pin', 'role', 'is_active'])
                    ->reject(fn ($value, $key) => $key === 'password' && blank($value))
                    ->all();
                $employee->user->update($userData);
                if (isset($outlet)) {
                    $employee->user->outlets()->sync([$outlet->id]);
                }
            }
        });

        return response()->json($employee->fresh()->load(['user', 'outlet', 'attendanceShift']));
    }

    public function destroy(Request $request, Employee $employee)
    {
        $this->ensureAccessible($request, $employee);
        abort_if($employee->attendanceLogs()->exists(), 422, 'Karyawan memiliki riwayat absensi dan hanya dapat dinonaktifkan.');
        DB::transaction(function () use ($employee): void {
            $employee->user?->update(['is_active' => false]);
            $employee->delete();
        });

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

    private function ensureRoleCanBeAssigned(
        Request $request,
        ?string $role,
        ?Employee $employee = null,
    ): void {
        if (! $role) {
            return;
        }
        $keepsExistingAdmin = $employee?->user?->role === 'admin'
            && $role === 'admin';
        if (
            $role === 'admin'
            && $request->user()?->role !== 'owner'
            && ! $keepsExistingAdmin
        ) {
            throw ValidationException::withMessages([
                'role' => 'Hanya owner yang dapat menunjuk admin baru.',
            ]);
        }
    }

    /**
     * @return array<string, array{label: string, description: string}>
     */
    private function roleOptions(): array
    {
        return [
            'admin' => [
                'label' => 'Admin',
                'description' => 'Mengelola katalog, karyawan, absensi, dan laporan.',
            ],
            'area_manager' => [
                'label' => 'Area Manager',
                'description' => 'Memantau beberapa outlet dan laporan area.',
            ],
            'outlet_manager' => [
                'label' => 'Outlet Manager',
                'description' => 'Menjalankan operasional satu outlet.',
            ],
            'cashier' => [
                'label' => 'Kasir',
                'description' => 'Menjalankan POS, pelanggan, dan pesanan.',
            ],
            'barista' => [
                'label' => 'Barista',
                'description' => 'Menerima serta memproses tiket minuman.',
            ],
            'kitchen_staff' => [
                'label' => 'Staf Dapur',
                'description' => 'Menerima serta memproses tiket makanan.',
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function employeeData(array $validated): array
    {
        return collect($validated)->only([
            'outlet_id',
            'attendance_shift_id',
            'employee_number',
            'name',
            'phone',
            'email',
            'position',
            'employment_status',
            'hire_date',
            'birth_date',
            'gender',
            'identity_number',
            'address',
            'emergency_contact_name',
            'emergency_contact_phone',
            'is_active',
        ])->all();
    }

    private function normalizeLoginFields(Request $request): void
    {
        $normalized = [];
        if ($request->exists('email')) {
            $email = Str::lower(trim((string) $request->input('email')));
            $normalized['email'] = $email === '' ? null : $email;
        }
        if ($request->exists('username')) {
            $username = Str::lower(trim((string) $request->input('username')));
            $normalized['username'] = $username === '' ? null : $username;
        }
        if ($request->exists('phone')) {
            $phone = preg_replace('/\D+/', '', (string) $request->input('phone')) ?? '';
            if (str_starts_with($phone, '0')) {
                $phone = '62'.substr($phone, 1);
            }
            $normalized['phone'] = $phone === '' ? null : $phone;
        }
        if ($normalized !== []) {
            $request->merge($normalized);
        }
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

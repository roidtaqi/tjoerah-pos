<?php

namespace App\Domains\Employee\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\Shift;
use Illuminate\Http\Request;

class EmployeeController extends Controller
{
    public function index(Request $request)
    {
        return Employee::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->paginate(100);
    }

    public function store(Request $request)
    {
        $employee = Employee::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'user_id' => 'nullable|integer|exists:users,id',
            'employee_number' => 'nullable|string|max:100',
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'position' => 'nullable|string|max:100',
            'hire_date' => 'nullable|date',
            'is_active' => 'boolean',
        ]));

        return response()->json($employee, 201);
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
}

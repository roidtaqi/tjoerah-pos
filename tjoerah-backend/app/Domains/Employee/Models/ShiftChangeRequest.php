<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class ShiftChangeRequest extends Model
{
    protected $guarded = [];

    protected $casts = [
        'requested_work_date' => 'date',
        'reviewed_at' => 'datetime',
    ];

    public function employee()
    {
        return $this->belongsTo(Employee::class);
    }

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function schedule()
    {
        return $this->belongsTo(EmployeeSchedule::class, 'employee_schedule_id');
    }

    public function requestedAttendanceShift()
    {
        return $this->belongsTo(AttendanceShift::class, 'requested_attendance_shift_id');
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function resultingSchedule()
    {
        return $this->belongsTo(EmployeeSchedule::class, 'resulting_schedule_id');
    }
}

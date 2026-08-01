<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class EmployeeSchedule extends Model
{
    protected $guarded = [];

    protected $casts = [
        'work_date' => 'date',
        'start_at' => 'datetime',
        'late_after_at' => 'datetime',
        'end_at' => 'datetime',
        'published_at' => 'datetime',
        'is_custom_time' => 'boolean',
        'revision' => 'integer',
    ];

    public function employee()
    {
        return $this->belongsTo(Employee::class);
    }

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function attendanceShift()
    {
        return $this->belongsTo(AttendanceShift::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function publisher()
    {
        return $this->belongsTo(User::class, 'published_by');
    }

    public function attendance()
    {
        return $this->hasOne(AttendanceLog::class);
    }

    public function audits()
    {
        return $this->hasMany(EmployeeScheduleAudit::class)->latest('created_at');
    }

    public function changeRequests()
    {
        return $this->hasMany(ShiftChangeRequest::class);
    }
}

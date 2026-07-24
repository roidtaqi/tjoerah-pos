<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Outlet;
use Illuminate\Database\Eloquent\Model;

class AttendanceShift extends Model
{
    protected $guarded = [];

    protected $casts = [
        'check_in_open_minutes' => 'integer',
        'is_active' => 'boolean',
        'sort_order' => 'integer',
    ];

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function employees()
    {
        return $this->hasMany(Employee::class);
    }

    public function schedules()
    {
        return $this->hasMany(EmployeeSchedule::class);
    }

    public function attendanceLogs()
    {
        return $this->hasMany(AttendanceLog::class);
    }
}

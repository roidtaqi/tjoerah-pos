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
        'end_at' => 'datetime',
    ];

    public function employee()
    {
        return $this->belongsTo(Employee::class);
    }

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function attendance()
    {
        return $this->hasOne(AttendanceLog::class);
    }
}

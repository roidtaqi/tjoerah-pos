<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Employee extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'hire_date' => 'date',
        'is_active' => 'boolean',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
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

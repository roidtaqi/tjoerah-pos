<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class EmployeeScheduleAudit extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected $casts = [
        'before' => 'array',
        'after' => 'array',
        'created_at' => 'datetime',
    ];

    public function schedule()
    {
        return $this->belongsTo(EmployeeSchedule::class, 'employee_schedule_id');
    }

    public function employee()
    {
        return $this->belongsTo(Employee::class);
    }

    public function actor()
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}

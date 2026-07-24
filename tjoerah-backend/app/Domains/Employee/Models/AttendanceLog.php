<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class AttendanceLog extends Model
{
    protected $guarded = [];

    protected $hidden = [
        'check_in_photo_path',
        'check_in_photo_hash',
        'check_out_photo_path',
        'check_out_photo_hash',
    ];

    protected $appends = [
        'has_check_in_photo',
        'has_check_out_photo',
    ];

    protected $casts = [
        'work_date' => 'date',
        'check_in_at' => 'datetime',
        'check_out_at' => 'datetime',
        'scheduled_start_at' => 'datetime',
        'scheduled_end_at' => 'datetime',
        'reviewed_at' => 'datetime',
        'check_in_device_at' => 'datetime',
        'check_out_device_at' => 'datetime',
        'late_minutes' => 'integer',
        'early_leave_minutes' => 'integer',
        'check_in_latitude' => 'float',
        'check_in_longitude' => 'float',
        'check_in_accuracy_meters' => 'float',
        'check_in_distance_meters' => 'float',
        'check_in_is_mock' => 'boolean',
        'check_in_outside_geofence' => 'boolean',
        'check_out_latitude' => 'float',
        'check_out_longitude' => 'float',
        'check_out_accuracy_meters' => 'float',
        'check_out_distance_meters' => 'float',
        'check_out_is_mock' => 'boolean',
        'check_out_outside_geofence' => 'boolean',
        'anomaly_flags' => 'array',
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

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function audits()
    {
        return $this->hasMany(AttendanceAudit::class);
    }

    public function getHasCheckInPhotoAttribute(): bool
    {
        return filled($this->check_in_photo_path);
    }

    public function getHasCheckOutPhotoAttribute(): bool
    {
        return filled($this->check_out_photo_path);
    }
}

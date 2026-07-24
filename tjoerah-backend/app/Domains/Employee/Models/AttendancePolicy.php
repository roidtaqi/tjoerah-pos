<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use Illuminate\Database\Eloquent\Model;

class AttendancePolicy extends Model
{
    protected $guarded = [];

    protected $casts = [
        'latitude' => 'float',
        'longitude' => 'float',
        'geofence_radius_meters' => 'integer',
        'maximum_accuracy_meters' => 'integer',
        'late_tolerance_minutes' => 'integer',
        'check_in_open_minutes' => 'integer',
        'photo_retention_days' => 'integer',
        'require_check_in_photo' => 'boolean',
        'require_check_out_photo' => 'boolean',
        'allow_outside_with_reason' => 'boolean',
        'is_active' => 'boolean',
    ];

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }
}

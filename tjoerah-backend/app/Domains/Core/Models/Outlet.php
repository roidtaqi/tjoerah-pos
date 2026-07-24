<?php

namespace App\Domains\Core\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\AttendanceShift;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Outlet extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class);
    }

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    public function brand()
    {
        return $this->belongsTo(Brand::class);
    }

    public function attendancePolicy()
    {
        return $this->hasOne(AttendancePolicy::class);
    }

    public function attendanceShifts()
    {
        return $this->hasMany(AttendanceShift::class);
    }
}

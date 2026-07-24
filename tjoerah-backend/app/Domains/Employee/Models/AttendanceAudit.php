<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class AttendanceAudit extends Model
{
    public const UPDATED_AT = null;

    protected $guarded = [];

    protected $casts = [
        'before' => 'array',
        'after' => 'array',
        'created_at' => 'datetime',
    ];

    public function attendance()
    {
        return $this->belongsTo(AttendanceLog::class, 'attendance_log_id');
    }

    public function actor()
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}

<?php

namespace App\Domains\Reporting\Models;

use Illuminate\Database\Eloquent\Model;

class AuditLog extends Model
{
    protected $guarded = [];

    protected $casts = [
        'old_values' => 'array',
        'new_values' => 'array',
    ];
}

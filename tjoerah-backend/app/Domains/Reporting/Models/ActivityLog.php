<?php

namespace App\Domains\Reporting\Models;

use Illuminate\Database\Eloquent\Model;

class ActivityLog extends Model
{
    protected $guarded = [];

    protected $casts = [
        'context' => 'array',
    ];
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SystemAlert extends Model
{
    protected $guarded = [];

    protected $casts = [
        'context' => 'array',
        'resolved_at' => 'datetime',
    ];
}

<?php

namespace App\Domains\Employee\Models;

use Illuminate\Database\Eloquent\Model;

class Shift extends Model
{
    protected $guarded = [];

    protected $casts = [
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
    ];
}

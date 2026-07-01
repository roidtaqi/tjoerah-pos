<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Model;

class TableSession extends Model
{
    protected $guarded = [];

    protected $casts = [
        'opened_at' => 'datetime',
        'closed_at' => 'datetime',
    ];
}

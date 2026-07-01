<?php

namespace App\Domains\Reporting\Models;

use Illuminate\Database\Eloquent\Model;

class PriceHistory extends Model
{
    protected $guarded = [];

    protected $casts = [
        'effective_at' => 'datetime',
    ];
}

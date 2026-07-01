<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class GoodsReceipt extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'items' => 'array',
        'received_at' => 'datetime',
    ];
}

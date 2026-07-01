<?php

namespace App\Domains\CRM\Models;

use Illuminate\Database\Eloquent\Model;

class CustomerReward extends Model
{
    protected $guarded = [];

    protected $casts = [
        'redeemed_at' => 'datetime',
    ];
}

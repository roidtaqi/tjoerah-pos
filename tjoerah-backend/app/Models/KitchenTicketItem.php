<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class KitchenTicketItem extends Model
{
    protected $guarded = [];

    protected $casts = [
        'modifiers' => 'array',
    ];
}

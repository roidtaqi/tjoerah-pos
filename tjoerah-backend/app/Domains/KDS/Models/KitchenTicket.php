<?php

namespace App\Domains\KDS\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class KitchenTicket extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'accepted_at' => 'datetime',
        'preparing_at' => 'datetime',
        'ready_at' => 'datetime',
        'completed_at' => 'datetime',
    ];

    public function items()
    {
        return $this->hasMany(\App\Domains\KDS\Models\KitchenTicketItem::class);
    }

    public function order()
    {
        return $this->belongsTo(\App\Domains\POS\Models\Order::class);
    }
}

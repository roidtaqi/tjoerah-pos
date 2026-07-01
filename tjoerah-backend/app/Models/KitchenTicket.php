<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class KitchenTicket extends Model
{
    protected $guarded = [];

    protected $casts = [
        'accepted_at' => 'datetime',
        'preparing_at' => 'datetime',
        'ready_at' => 'datetime',
        'completed_at' => 'datetime',
    ];

    public function items()
    {
        return $this->hasMany(KitchenTicketItem::class);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}

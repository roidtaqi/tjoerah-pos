<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Order extends Model
{
    use HasUuids, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'meta' => 'array',
        'completed_at' => 'datetime',
    ];

    public function items()
    {
        return $this->hasMany(\App\Domains\POS\Models\OrderItem::class);
    }

    public function payments()
    {
        return $this->hasMany(\App\Domains\POS\Models\Payment::class);
    }

    public function kitchenTickets()
    {
        return $this->hasMany(\App\Domains\KDS\Models\KitchenTicket::class);
    }
}

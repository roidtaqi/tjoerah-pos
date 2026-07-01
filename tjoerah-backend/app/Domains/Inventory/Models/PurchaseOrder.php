<?php

namespace App\Domains\Inventory\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class PurchaseOrder extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'ordered_at' => 'date',
        'expected_at' => 'date',
    ];

    public function items()
    {
        return $this->hasMany(\App\Domains\Inventory\Models\PurchaseOrderItem::class);
    }
}

<?php

namespace App\Domains\Inventory\Models;

use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\OrderItem;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Wastage extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'original_stock_consumed' => 'boolean',
        'recipe_version' => 'integer',
        'quantity' => 'decimal:4',
        'value' => 'decimal:2',
    ];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function orderItem()
    {
        return $this->belongsTo(OrderItem::class);
    }
}

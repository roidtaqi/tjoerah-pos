<?php

namespace App\Domains\Inventory\Models;

use Illuminate\Database\Eloquent\Model;

class StockMovement extends Model
{
    protected $guarded = [];

    public function inventoryItem()
    {
        return $this->belongsTo(\App\Domains\Inventory\Models\InventoryItem::class);
    }

    public function warehouse()
    {
        return $this->belongsTo(\App\Domains\Inventory\Models\Warehouse::class);
    }
}

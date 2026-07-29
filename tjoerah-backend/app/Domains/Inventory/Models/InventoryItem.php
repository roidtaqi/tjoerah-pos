<?php

namespace App\Domains\Inventory\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class InventoryItem extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'weighted_average_cost' => 'decimal:4',
            'minimum_stock' => 'decimal:4',
            'is_active' => 'boolean',
        ];
    }
}

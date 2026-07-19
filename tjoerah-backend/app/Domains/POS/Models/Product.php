<?php

namespace App\Domains\POS\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'base_price' => 'decimal:2',
            'is_active' => 'boolean',
            'track_inventory' => 'boolean',
            'sla_minutes' => 'integer',
        ];
    }

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    public function variants()
    {
        return $this->hasMany(ProductVariant::class);
    }

    public function modifierGroups()
    {
        return $this->belongsToMany(ModifierGroup::class);
    }
}

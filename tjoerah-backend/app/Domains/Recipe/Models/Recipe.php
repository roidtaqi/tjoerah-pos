<?php

namespace App\Domains\Recipe\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use App\Domains\POS\Models\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Recipe extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'active_version' => 'integer',
            'yield_quantity' => 'decimal:4',
            'current_cost' => 'decimal:4',
        ];
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function items()
    {
        return $this->hasMany(RecipeItem::class);
    }

    public function versions()
    {
        return $this->hasMany(RecipeVersion::class);
    }

    public function latestVersionRecord()
    {
        return $this->hasOne(RecipeVersion::class)->ofMany('version', 'max');
    }
}

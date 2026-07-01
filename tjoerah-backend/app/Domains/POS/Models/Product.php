<?php

namespace App\Domains\POS\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function category()
    {
        return $this->belongsTo(\App\Domains\POS\Models\Category::class);
    }

    public function variants()
    {
        return $this->hasMany(\App\Domains\POS\Models\ProductVariant::class);
    }

    public function modifierGroups()
    {
        return $this->belongsToMany(\App\Domains\POS\Models\ModifierGroup::class);
    }
}

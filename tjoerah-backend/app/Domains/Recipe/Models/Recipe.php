<?php

namespace App\Domains\Recipe\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Recipe extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function items()
    {
        return $this->hasMany(\App\Domains\Recipe\Models\RecipeItem::class);
    }

    public function versions()
    {
        return $this->hasMany(\App\Domains\Recipe\Models\RecipeVersion::class);
    }
}

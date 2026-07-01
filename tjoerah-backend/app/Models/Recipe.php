<?php

namespace App\Models;

use App\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Recipe extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function items()
    {
        return $this->hasMany(RecipeItem::class);
    }

    public function versions()
    {
        return $this->hasMany(RecipeVersion::class);
    }
}

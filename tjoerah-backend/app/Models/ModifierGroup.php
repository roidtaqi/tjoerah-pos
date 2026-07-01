<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ModifierGroup extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    public function options()
    {
        return $this->hasMany(ModifierOption::class);
    }

    public function products()
    {
        return $this->belongsToMany(Product::class);
    }
}

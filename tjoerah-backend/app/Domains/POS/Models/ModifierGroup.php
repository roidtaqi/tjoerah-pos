<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ModifierGroup extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    public function options()
    {
        return $this->hasMany(\App\Domains\POS\Models\ModifierOption::class);
    }

    public function products()
    {
        return $this->belongsToMany(\App\Domains\POS\Models\Product::class);
    }
}

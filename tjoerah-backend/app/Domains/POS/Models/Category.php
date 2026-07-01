<?php

namespace App\Domains\POS\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Category extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function parent()
    {
        return $this->belongsTo(\App\Domains\POS\Models\Category::class, 'parent_id');
    }

    public function children()
    {
        return $this->hasMany(\App\Domains\POS\Models\Category::class, 'parent_id');
    }

    public function products()
    {
        return $this->hasMany(\App\Domains\POS\Models\Product::class);
    }
}

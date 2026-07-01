<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ProductVariant extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    public function product()
    {
        return $this->belongsTo(\App\Domains\POS\Models\Product::class);
    }
}

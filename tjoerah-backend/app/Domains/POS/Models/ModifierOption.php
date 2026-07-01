<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ModifierOption extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    public function group()
    {
        return $this->belongsTo(\App\Domains\POS\Models\ModifierGroup::class, 'modifier_group_id');
    }
}

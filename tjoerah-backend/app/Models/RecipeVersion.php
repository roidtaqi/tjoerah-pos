<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class RecipeVersion extends Model
{
    protected $guarded = [];

    protected $casts = [
        'effective_at' => 'datetime',
    ];
}

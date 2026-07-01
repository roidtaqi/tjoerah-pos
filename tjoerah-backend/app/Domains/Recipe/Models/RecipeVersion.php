<?php

namespace App\Domains\Recipe\Models;

use Illuminate\Database\Eloquent\Model;

class RecipeVersion extends Model
{
    protected $guarded = [];

    protected $casts = [
        'effective_at' => 'datetime',
    ];
}

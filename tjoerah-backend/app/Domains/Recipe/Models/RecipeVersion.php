<?php

namespace App\Domains\Recipe\Models;

use App\Domains\Core\Models\User;
use Illuminate\Database\Eloquent\Model;

class RecipeVersion extends Model
{
    protected $guarded = [];

    protected $casts = [
        'effective_at' => 'datetime',
        'version' => 'integer',
        'total_cost' => 'decimal:4',
        'waste_percent' => 'decimal:4',
    ];

    public function recipe()
    {
        return $this->belongsTo(Recipe::class);
    }

    public function items()
    {
        return $this->hasMany(RecipeItem::class);
    }

    public function approvedBy()
    {
        return $this->belongsTo(User::class, 'approved_by');
    }
}

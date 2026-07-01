<?php

namespace App\Domains\CRM\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Promotion extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'rules' => 'array',
        'starts_at' => 'date',
        'ends_at' => 'date',
    ];
}

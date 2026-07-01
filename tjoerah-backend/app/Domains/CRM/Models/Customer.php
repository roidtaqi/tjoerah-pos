<?php

namespace App\Domains\CRM\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'birthday' => 'date',
        'last_purchase_at' => 'datetime',
    ];
}

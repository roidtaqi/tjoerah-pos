<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Employee extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'hire_date' => 'date',
    ];
}

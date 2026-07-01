<?php

namespace App\Domains\Inventory\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Warehouse extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];
}

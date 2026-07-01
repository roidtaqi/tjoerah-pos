<?php

namespace App\Domains\Inventory\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Wastage extends Model
{
    use SoftDeletes;

    protected $guarded = [];
}

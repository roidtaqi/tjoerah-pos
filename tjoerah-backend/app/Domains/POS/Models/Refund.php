<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Refund extends Model
{
    use HasUuids, SoftDeletes;

    protected $guarded = [];
}

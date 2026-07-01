<?php

namespace App\Domains\POS\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class DiningTable extends Model
{
    use SoftDeletes;

    protected $table = 'tables';
    protected $guarded = [];
}

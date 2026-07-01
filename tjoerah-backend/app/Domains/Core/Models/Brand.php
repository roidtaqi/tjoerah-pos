<?php

namespace App\Domains\Core\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Brand extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function company()
    {
        return $this->belongsTo(\App\Domains\Core\Models\Company::class);
    }

    public function outlets()
    {
        return $this->hasMany(\App\Domains\Core\Models\Outlet::class);
    }
}

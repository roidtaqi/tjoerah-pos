<?php

namespace App\Domains\Core\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Company extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function brands()
    {
        return $this->hasMany(\App\Domains\Core\Models\Brand::class);
    }

    public function outlets()
    {
        return $this->hasMany(\App\Domains\Core\Models\Outlet::class);
    }
}

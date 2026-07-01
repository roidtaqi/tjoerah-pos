<?php

namespace App\Models;

use App\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Company extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function brands()
    {
        return $this->hasMany(Brand::class);
    }

    public function outlets()
    {
        return $this->hasMany(Outlet::class);
    }
}

<?php

namespace App\Domains\Core\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

class Outlet extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(\App\Domains\Core\Models\User::class);
    }

    public function company()
    {
        return $this->belongsTo(\App\Domains\Core\Models\Company::class);
    }

    public function brand()
    {
        return $this->belongsTo(\App\Domains\Core\Models\Brand::class);
    }
}

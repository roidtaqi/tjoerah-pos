<?php

namespace App\Domains\Core\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Role extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    public function permissions()
    {
        return $this->belongsToMany(\App\Domains\Core\Models\Permission::class, 'role_permissions');
    }
}

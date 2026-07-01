<?php

namespace App\Domains\Core\Models;

use Illuminate\Database\Eloquent\Model;

class Permission extends Model
{
    protected $guarded = [];

    public function roles()
    {
        return $this->belongsToMany(\App\Domains\Core\Models\Role::class, 'role_permissions');
    }
}

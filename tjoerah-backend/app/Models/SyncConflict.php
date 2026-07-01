<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SyncConflict extends Model
{
    protected $guarded = [];

    protected $casts = [
        'client_payload' => 'array',
        'server_payload' => 'array',
    ];
}

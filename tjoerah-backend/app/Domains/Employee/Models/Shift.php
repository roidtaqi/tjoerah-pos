<?php

namespace App\Domains\Employee\Models;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\CashMovement;
use Illuminate\Database\Eloquent\Model;

class Shift extends Model
{
    protected $guarded = [];

    protected $casts = [
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
        'opening_cash' => 'decimal:2',
        'closing_cash' => 'decimal:2',
    ];

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function openedBy()
    {
        return $this->belongsTo(User::class, 'opened_by');
    }

    public function closedBy()
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    public function movements()
    {
        return $this->hasMany(CashMovement::class);
    }
}

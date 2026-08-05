<?php

namespace App\Domains\POS\Models;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\Shift;
use Illuminate\Database\Eloquent\Model;

class CashMovement extends Model
{
    protected $guarded = [];

    protected $casts = [
        'amount' => 'decimal:2',
        'occurred_at' => 'datetime',
        'meta' => 'array',
    ];

    public function outlet()
    {
        return $this->belongsTo(Outlet::class);
    }

    public function shift()
    {
        return $this->belongsTo(Shift::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function signedAmount(): float
    {
        return in_array($this->type, ['refund', 'cash_out', 'adjustment_out'], true)
            ? -(float) $this->amount
            : (float) $this->amount;
    }
}

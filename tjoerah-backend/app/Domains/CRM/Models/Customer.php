<?php

namespace App\Domains\CRM\Models;

use App\Domains\Core\Models\Concerns\HasUuid;
use App\Domains\POS\Models\Order;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use HasUuid, SoftDeletes;

    protected $guarded = [];

    protected $casts = [
        'birthday' => 'date',
        'last_purchase_at' => 'datetime',
    ];

    public function orders()
    {
        return $this->hasMany(Order::class);
    }
}

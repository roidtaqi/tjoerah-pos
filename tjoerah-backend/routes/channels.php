<?php

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});

Broadcast::channel('kds.outlet.{outletId}', function (User $user, int $outletId): bool {
    if ($user->company_id) {
        return Outlet::query()
            ->whereKey($outletId)
            ->where('company_id', $user->company_id)
            ->where('is_active', true)
            ->exists();
    }

    return $user->outlets()
        ->whereKey($outletId)
        ->where('is_active', true)
        ->exists();
}, ['guards' => ['api']]);

Broadcast::channel('cash.outlet.{outletId}', function (User $user, int $outletId): bool {
    if ($user->company_id) {
        return Outlet::query()
            ->whereKey($outletId)
            ->where('company_id', $user->company_id)
            ->where('is_active', true)
            ->exists();
    }

    if ((int) $user->employee?->outlet_id === $outletId) {
        return Outlet::query()
            ->whereKey($outletId)
            ->where('is_active', true)
            ->exists();
    }

    return $user->outlets()
        ->whereKey($outletId)
        ->where('is_active', true)
        ->exists();
}, ['guards' => ['api']]);

<?php

namespace App\Domains\POS\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class TransactionSettingsController extends Controller
{
    public function show(Request $request)
    {
        $outlet = $this->resolveOutlet($request);

        return response()->json([
            'data' => $this->settings($outlet),
        ]);
    }

    public function update(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'tax_enabled' => 'required|boolean',
            'tax_rate' => 'required|numeric|min:0|max:100',
            'kds_mode' => 'sometimes|string|in:manual,automatic',
        ]);

        $outlet = $this->resolveOutlet($request);
        $outlet->update([
            'tax_enabled' => $validated['tax_enabled'],
            'tax_rate' => $validated['tax_rate'],
            'kds_mode' => $validated['kds_mode'] ?? $outlet->kds_mode,
        ]);

        return response()->json([
            'message' => 'Pengaturan transaksi berhasil disimpan.',
            'data' => $this->settings($outlet->refresh()),
        ]);
    }

    private function resolveOutlet(Request $request): Outlet
    {
        $outletId = $request->integer('outlet_id');
        if (! $outletId) {
            $outletId = $request->user()?->outlets()->value('outlets.id');
        }

        $outlet = $outletId ? Outlet::find($outletId) : null;
        if (! $outlet) {
            throw ValidationException::withMessages([
                'outlet_id' => 'Outlet aktif belum tersedia.',
            ]);
        }

        $companyId = $request->user()?->company_id;
        if ($companyId && (int) $outlet->company_id !== (int) $companyId) {
            abort(404);
        }

        return $outlet;
    }

    private function settings(Outlet $outlet): array
    {
        return [
            'outlet_id' => $outlet->id,
            'tax_enabled' => (bool) $outlet->tax_enabled,
            'tax_rate' => (float) $outlet->tax_rate,
            'kds_mode' => $outlet->kds_mode ?: 'manual',
        ];
    }
}

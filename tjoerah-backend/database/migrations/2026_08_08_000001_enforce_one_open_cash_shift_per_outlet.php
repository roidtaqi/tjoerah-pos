<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private const INDEX = 'shifts_one_open_per_outlet_unique';

    public function up(): void
    {
        $outletIds = DB::table('shifts')
            ->where('status', 'open')
            ->distinct()
            ->pluck('outlet_id');

        foreach ($outletIds as $outletId) {
            $activeIds = DB::table('shifts')
                ->where('outlet_id', $outletId)
                ->where('status', 'open')
                ->orderByDesc('started_at')
                ->orderByDesc('id')
                ->pluck('id');

            if ($activeIds->count() <= 1) {
                continue;
            }

            DB::table('shifts')
                ->whereIn('id', $activeIds->slice(1)->all())
                ->update([
                    'status' => 'closed',
                    'ended_at' => now(),
                    'updated_at' => now(),
                ]);
        }

        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) {
            DB::statement(sprintf(
                "CREATE UNIQUE INDEX %s ON shifts (outlet_id) WHERE status = 'open'",
                self::INDEX,
            ));
        }
    }

    public function down(): void
    {
        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) {
            DB::statement('DROP INDEX IF EXISTS '.self::INDEX);
        }
    }
};

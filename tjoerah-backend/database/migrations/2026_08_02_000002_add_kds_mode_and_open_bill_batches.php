<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('outlets', function (Blueprint $table) {
            $table->string('kds_mode')->default('manual')->after('tax_rate');
        });

        Schema::table('order_items', function (Blueprint $table) {
            $table->unsignedInteger('submission_batch')->default(1)->after('notes');
            $table->timestamp('submitted_at')->nullable()->after('submission_batch');
            $table->timestamp('inventory_deducted_at')->nullable()->after('submitted_at');
            $table->index(['order_id', 'submission_batch']);
        });

        DB::table('order_items')
            ->select(['id', 'order_id', 'created_at'])
            ->orderBy('id')
            ->chunk(500, function ($items): void {
                $deductedAtByOrder = DB::table('orders')
                    ->whereIn('id', $items->pluck('order_id')->unique())
                    ->pluck('inventory_deducted_at', 'id');

                foreach ($items as $item) {
                    DB::table('order_items')->where('id', $item->id)->update([
                        'submitted_at' => $item->created_at,
                        'inventory_deducted_at' => $deductedAtByOrder[$item->order_id] ?? null,
                    ]);
                }
            });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropIndex(['order_id', 'submission_batch']);
            $table->dropColumn([
                'submission_batch',
                'submitted_at',
                'inventory_deducted_at',
            ]);
        });

        Schema::table('outlets', function (Blueprint $table) {
            $table->dropColumn('kds_mode');
        });
    }
};

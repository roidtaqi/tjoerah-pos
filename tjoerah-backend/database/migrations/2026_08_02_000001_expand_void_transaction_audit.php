<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('void_transactions', function (Blueprint $table) {
            $table->string('previous_status')->nullable()->after('amount');
            $table->string('inventory_outcome')->default('no_stock_return')->after('previous_status');
            $table->foreignUuid('refund_id')->nullable()->after('inventory_outcome')->constrained()->nullOnDelete();
            $table->timestamp('stock_restored_at')->nullable()->after('refund_id');
            $table->json('meta')->nullable()->after('reason');
        });
    }

    public function down(): void
    {
        Schema::table('void_transactions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('refund_id');
            $table->dropColumn([
                'previous_status',
                'inventory_outcome',
                'stock_restored_at',
                'meta',
            ]);
        });
    }
};

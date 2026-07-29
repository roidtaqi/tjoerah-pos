<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('outlets', function (Blueprint $table) {
            $table->boolean('tax_enabled')->default(true)->after('timezone');
            $table->decimal('tax_rate', 5, 2)->default(11)->after('tax_enabled');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->decimal('tax_rate', 5, 2)->default(0)->after('tax');
            $table->timestamp('submitted_at')->nullable()->after('meta');
            $table->timestamp('inventory_deducted_at')->nullable()->after('submitted_at');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn([
                'tax_rate',
                'submitted_at',
                'inventory_deducted_at',
            ]);
        });

        Schema::table('outlets', function (Blueprint $table) {
            $table->dropColumn(['tax_enabled', 'tax_rate']);
        });
    }
};

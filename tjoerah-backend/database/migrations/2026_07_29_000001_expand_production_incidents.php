<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wastages', function (Blueprint $table) {
            $table->foreignUuid('order_id')->nullable()->after('outlet_id')->constrained()->nullOnDelete();
            $table->foreignUuid('order_item_id')->nullable()->after('order_id')->constrained()->nullOnDelete();
            $table->string('resolution')->nullable()->after('waste_type');
            $table->unsignedInteger('recipe_version')->nullable()->after('resolution');
            $table->boolean('original_stock_consumed')->default(false)->after('recipe_version');
        });

        Schema::table('refunds', function (Blueprint $table) {
            $table->foreignUuid('order_item_id')->nullable()->after('order_id')->constrained()->nullOnDelete();
            $table->unsignedInteger('quantity')->nullable()->after('amount');
            $table->string('inventory_outcome')->default('no_stock_return')->after('type');
        });
    }

    public function down(): void
    {
        Schema::table('refunds', function (Blueprint $table) {
            $table->dropConstrainedForeignId('order_item_id');
            $table->dropColumn(['quantity', 'inventory_outcome']);
        });

        Schema::table('wastages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('order_item_id');
            $table->dropConstrainedForeignId('order_id');
            $table->dropColumn([
                'resolution',
                'recipe_version',
                'original_stock_consumed',
            ]);
        });
    }
};

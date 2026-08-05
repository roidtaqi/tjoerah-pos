<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cash_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $table->foreignId('shift_id')->nullable()->constrained('shifts')->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('type', 50);
            $table->string('category', 100);
            $table->decimal('amount', 14, 2);
            $table->text('note')->nullable();
            $table->string('reference_type')->nullable();
            $table->string('reference_id')->nullable();
            $table->string('reference_number')->nullable();
            $table->string('source_key')->nullable()->unique();
            $table->string('evidence_path')->nullable();
            $table->timestamp('occurred_at');
            $table->json('meta')->nullable();
            $table->timestamps();

            $table->index(['outlet_id', 'occurred_at']);
            $table->index(['shift_id', 'occurred_at']);
            $table->index(['reference_type', 'reference_id']);
        });

        Schema::table('refunds', function (Blueprint $table) {
            $table->string('method', 50)->nullable()->after('amount');
            $table->json('meta')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('refunds', function (Blueprint $table) {
            $table->dropColumn(['method', 'meta']);
        });

        Schema::dropIfExists('cash_movements');
    }
};

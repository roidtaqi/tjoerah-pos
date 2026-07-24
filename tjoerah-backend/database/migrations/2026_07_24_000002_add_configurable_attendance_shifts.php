<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_shifts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->string('start_time', 5);
            $table->string('late_after_time', 5);
            $table->string('end_time', 5);
            $table->unsignedSmallInteger('check_in_open_minutes')->default(60);
            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['outlet_id', 'name']);
            $table->index(['outlet_id', 'is_active', 'sort_order']);
        });

        $now = now();
        DB::table('outlets')
            ->whereNull('deleted_at')
            ->select(['id', 'company_id'])
            ->orderBy('id')
            ->each(function (object $outlet) use ($now): void {
                DB::table('attendance_shifts')->insert([
                    [
                        'company_id' => $outlet->company_id,
                        'outlet_id' => $outlet->id,
                        'name' => 'Shift Pagi',
                        'start_time' => '07:30',
                        'late_after_time' => '07:45',
                        'end_time' => '15:30',
                        'check_in_open_minutes' => 60,
                        'is_active' => true,
                        'sort_order' => 1,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ],
                    [
                        'company_id' => $outlet->company_id,
                        'outlet_id' => $outlet->id,
                        'name' => 'Shift Kedua',
                        'start_time' => '15:30',
                        'late_after_time' => '15:45',
                        'end_time' => '23:30',
                        'check_in_open_minutes' => 60,
                        'is_active' => true,
                        'sort_order' => 2,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ],
                ]);
            });

        Schema::table('employees', function (Blueprint $table) {
            $table->foreignId('attendance_shift_id')
                ->nullable()
                ->after('outlet_id')
                ->constrained('attendance_shifts')
                ->nullOnDelete();
        });

        Schema::table('employee_schedules', function (Blueprint $table) {
            $table->foreignId('attendance_shift_id')
                ->nullable()
                ->after('outlet_id')
                ->constrained('attendance_shifts')
                ->nullOnDelete();
            $table->timestamp('late_after_at')->nullable()->after('start_at');
        });

        Schema::table('attendance_logs', function (Blueprint $table) {
            $table->foreignId('attendance_shift_id')
                ->nullable()
                ->after('employee_schedule_id')
                ->constrained('attendance_shifts')
                ->nullOnDelete();
            $table->timestamp('scheduled_late_after_at')
                ->nullable()
                ->after('scheduled_start_at');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_logs', function (Blueprint $table) {
            $table->dropForeign(['attendance_shift_id']);
            $table->dropColumn([
                'attendance_shift_id',
                'scheduled_late_after_at',
            ]);
        });

        Schema::table('employee_schedules', function (Blueprint $table) {
            $table->dropForeign(['attendance_shift_id']);
            $table->dropColumn(['attendance_shift_id', 'late_after_at']);
        });

        Schema::table('employees', function (Blueprint $table) {
            $table->dropForeign(['attendance_shift_id']);
            $table->dropColumn('attendance_shift_id');
        });

        Schema::dropIfExists('attendance_shifts');
    }
};

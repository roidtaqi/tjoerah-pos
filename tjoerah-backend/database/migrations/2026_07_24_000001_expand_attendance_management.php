<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_policies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('outlet_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('timezone')->default('Asia/Makassar');
            $table->string('work_start_time', 5)->default('08:00');
            $table->string('work_end_time', 5)->default('17:00');
            $table->unsignedSmallInteger('late_tolerance_minutes')->default(10);
            $table->unsignedSmallInteger('check_in_open_minutes')->default(60);
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->unsignedInteger('geofence_radius_meters')->default(100);
            $table->unsignedInteger('maximum_accuracy_meters')->default(100);
            $table->boolean('require_check_in_photo')->default(true);
            $table->boolean('require_check_out_photo')->default(true);
            $table->boolean('allow_outside_with_reason')->default(true);
            $table->unsignedSmallInteger('photo_retention_days')->default(180);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('employee_schedules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('employee_id')->constrained()->cascadeOnDelete();
            $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $table->date('work_date');
            $table->timestamp('start_at');
            $table->timestamp('end_at');
            $table->string('shift_name')->default('Reguler');
            $table->string('status')->default('scheduled');
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['employee_id', 'start_at']);
            $table->index(['outlet_id', 'work_date', 'status']);
        });

        Schema::table('attendance_logs', function (Blueprint $table) {
            $table->date('work_date')->nullable()->after('outlet_id');
            $table->foreignId('employee_schedule_id')->nullable()->after('work_date')->constrained()->nullOnDelete();
            $table->timestamp('scheduled_start_at')->nullable()->after('employee_schedule_id');
            $table->timestamp('scheduled_end_at')->nullable()->after('scheduled_start_at');
            $table->string('punctuality_status')->nullable()->after('check_out_at');
            $table->unsignedInteger('late_minutes')->default(0)->after('punctuality_status');
            $table->unsignedInteger('early_leave_minutes')->default(0)->after('late_minutes');
            $table->string('review_status')->default('approved')->after('early_leave_minutes');
            $table->text('review_notes')->nullable()->after('review_status');
            $table->foreignId('reviewed_by')->nullable()->after('review_notes')->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable()->after('reviewed_by');

            $table->string('check_in_photo_path')->nullable();
            $table->string('check_in_photo_hash', 64)->nullable();
            $table->decimal('check_in_latitude', 10, 7)->nullable();
            $table->decimal('check_in_longitude', 10, 7)->nullable();
            $table->decimal('check_in_accuracy_meters', 10, 2)->nullable();
            $table->decimal('check_in_distance_meters', 10, 2)->nullable();
            $table->boolean('check_in_is_mock')->default(false);
            $table->boolean('check_in_outside_geofence')->default(false);
            $table->text('check_in_outside_reason')->nullable();
            $table->timestamp('check_in_device_at')->nullable();

            $table->string('check_out_photo_path')->nullable();
            $table->string('check_out_photo_hash', 64)->nullable();
            $table->decimal('check_out_latitude', 10, 7)->nullable();
            $table->decimal('check_out_longitude', 10, 7)->nullable();
            $table->decimal('check_out_accuracy_meters', 10, 2)->nullable();
            $table->decimal('check_out_distance_meters', 10, 2)->nullable();
            $table->boolean('check_out_is_mock')->default(false);
            $table->boolean('check_out_outside_geofence')->default(false);
            $table->text('check_out_outside_reason')->nullable();
            $table->timestamp('check_out_device_at')->nullable();

            $table->string('device_id')->nullable();
            $table->uuid('check_in_request_id')->nullable()->unique();
            $table->uuid('check_out_request_id')->nullable()->unique();
            $table->json('anomaly_flags')->nullable();

            $table->index(['outlet_id', 'work_date', 'punctuality_status'], 'attendance_report_index');
            $table->index(['review_status', 'work_date']);
        });

        Schema::create('attendance_audits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('attendance_log_id')->constrained()->cascadeOnDelete();
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action');
            $table->json('before')->nullable();
            $table->json('after')->nullable();
            $table->text('reason')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['attendance_log_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_audits');

        Schema::table('attendance_logs', function (Blueprint $table) {
            $table->dropIndex('attendance_report_index');
            $table->dropIndex(['review_status', 'work_date']);
            $table->dropForeign(['employee_schedule_id']);
            $table->dropForeign(['reviewed_by']);
            $table->dropColumn([
                'work_date',
                'employee_schedule_id',
                'scheduled_start_at',
                'scheduled_end_at',
                'punctuality_status',
                'late_minutes',
                'early_leave_minutes',
                'review_status',
                'review_notes',
                'reviewed_by',
                'reviewed_at',
                'check_in_photo_path',
                'check_in_photo_hash',
                'check_in_latitude',
                'check_in_longitude',
                'check_in_accuracy_meters',
                'check_in_distance_meters',
                'check_in_is_mock',
                'check_in_outside_geofence',
                'check_in_outside_reason',
                'check_in_device_at',
                'check_out_photo_path',
                'check_out_photo_hash',
                'check_out_latitude',
                'check_out_longitude',
                'check_out_accuracy_meters',
                'check_out_distance_meters',
                'check_out_is_mock',
                'check_out_outside_geofence',
                'check_out_outside_reason',
                'check_out_device_at',
                'device_id',
                'check_in_request_id',
                'check_out_request_id',
                'anomaly_flags',
            ]);
        });

        Schema::dropIfExists('employee_schedules');
        Schema::dropIfExists('attendance_policies');
    }
};

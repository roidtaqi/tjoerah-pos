<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('employee_schedules', function (Blueprint $table) {
            $table->string('publication_status', 20)->default('published')->after('status');
            $table->timestamp('published_at')->nullable()->after('publication_status');
            $table->foreignId('published_by')->nullable()->after('published_at')->constrained('users')->nullOnDelete();
            $table->boolean('is_custom_time')->default(false)->after('published_by');
            $table->text('change_reason')->nullable()->after('notes');
            $table->unsignedInteger('revision')->default(1)->after('change_reason');

            $table->index(['outlet_id', 'work_date', 'publication_status'], 'schedule_roster_index');
            $table->index(['employee_id', 'work_date'], 'schedule_employee_date_index');
        });

        Schema::create('employee_schedule_audits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('employee_schedule_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained()->cascadeOnDelete();
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 50);
            $table->json('before')->nullable();
            $table->json('after')->nullable();
            $table->text('reason')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['employee_schedule_id', 'created_at'], 'schedule_audit_index');
        });

        Schema::create('shift_change_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('employee_id')->constrained()->cascadeOnDelete();
            $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_schedule_id')->nullable()->constrained()->nullOnDelete();
            $table->date('requested_work_date');
            $table->foreignId('requested_attendance_shift_id')->nullable()->constrained('attendance_shifts')->nullOnDelete();
            $table->string('requested_status', 20)->default('scheduled');
            $table->string('requested_start_time', 5)->nullable();
            $table->string('requested_late_after_time', 5)->nullable();
            $table->string('requested_end_time', 5)->nullable();
            $table->text('reason');
            $table->string('status', 20)->default('pending');
            $table->text('response_notes')->nullable();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->foreignId('resulting_schedule_id')->nullable()->constrained('employee_schedules')->nullOnDelete();
            $table->timestamps();

            $table->index(['outlet_id', 'status', 'requested_work_date'], 'shift_request_admin_index');
            $table->index(['employee_id', 'status', 'requested_work_date'], 'shift_request_employee_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shift_change_requests');
        Schema::dropIfExists('employee_schedule_audits');

        Schema::table('employee_schedules', function (Blueprint $table) {
            $table->dropIndex('schedule_roster_index');
            $table->dropIndex('schedule_employee_date_index');
            $table->dropForeign(['published_by']);
            $table->dropColumn([
                'publication_status',
                'published_at',
                'published_by',
                'is_custom_time',
                'change_reason',
                'revision',
            ]);
        });
    }
};

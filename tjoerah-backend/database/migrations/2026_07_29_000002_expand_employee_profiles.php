<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('employees', function (Blueprint $table) {
            $table->date('birth_date')->nullable()->after('hire_date');
            $table->string('gender', 20)->nullable()->after('birth_date');
            $table->string('identity_number', 100)->nullable()->after('gender');
            $table->string('employment_status', 30)->default('permanent')->after('position');
            $table->text('address')->nullable()->after('identity_number');
            $table->string('emergency_contact_name')->nullable()->after('address');
            $table->string('emergency_contact_phone', 50)->nullable()->after('emergency_contact_name');

            $table->index(['company_id', 'employment_status', 'is_active'], 'employees_status_index');
        });
    }

    public function down(): void
    {
        Schema::table('employees', function (Blueprint $table) {
            $table->dropIndex('employees_status_index');
            $table->dropColumn([
                'birth_date',
                'gender',
                'identity_number',
                'employment_status',
                'address',
                'emergency_contact_name',
                'emergency_contact_phone',
            ]);
        });
    }
};

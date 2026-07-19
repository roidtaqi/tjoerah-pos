<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check');
            DB::statement("ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('owner', 'admin', 'area_manager', 'outlet_manager', 'cashier', 'barista', 'kitchen_staff'))");
        }

        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::statement("ALTER TABLE users MODIFY role ENUM('owner', 'admin', 'area_manager', 'outlet_manager', 'cashier', 'barista', 'kitchen_staff') NOT NULL DEFAULT 'cashier'");
        }
    }

    public function down(): void
    {
        DB::table('users')->where('role', 'admin')->update(['role' => 'owner']);

        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check');
            DB::statement("ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('owner', 'area_manager', 'outlet_manager', 'cashier', 'barista', 'kitchen_staff'))");
        }

        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::statement("ALTER TABLE users MODIFY role ENUM('owner', 'area_manager', 'outlet_manager', 'cashier', 'barista', 'kitchen_staff') NOT NULL DEFAULT 'cashier'");
        }
    }
};

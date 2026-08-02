<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('username', 100)->nullable()->after('name');
            $table->string('phone', 50)->nullable()->after('email');
        });

        $this->backfillEmployeeIdentifiers();

        Schema::table('users', function (Blueprint $table) {
            $table->unique('username');
            $table->unique('phone');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['username']);
            $table->dropUnique(['phone']);
            $table->dropColumn(['username', 'phone']);
        });
    }

    private function backfillEmployeeIdentifiers(): void
    {
        $usedUsernames = [];
        $usedPhones = [];
        $assignedIdentifiers = [];

        DB::table('employees')
            ->select(['id', 'user_id', 'employee_number', 'phone'])
            ->whereNotNull('user_id')
            ->orderBy('id')
            ->get()
            ->each(function (object $employee) use (&$usedUsernames, &$usedPhones, &$assignedIdentifiers): void {
                $updates = [];
                $assigned = $assignedIdentifiers[$employee->user_id] ?? [
                    'username' => false,
                    'phone' => false,
                ];
                $username = $this->normalizeUsername($employee->employee_number);
                if (! $assigned['username'] && $username !== null && ! isset($usedUsernames[$username])) {
                    $updates['username'] = $username;
                    $usedUsernames[$username] = true;
                    $assigned['username'] = true;
                }

                $phone = $this->normalizePhone($employee->phone);
                if (! $assigned['phone'] && $phone !== null && ! isset($usedPhones[$phone])) {
                    $updates['phone'] = $phone;
                    $usedPhones[$phone] = true;
                    $assigned['phone'] = true;
                }
                $assignedIdentifiers[$employee->user_id] = $assigned;

                if ($updates !== []) {
                    DB::table('users')
                        ->where('id', $employee->user_id)
                        ->update($updates);
                }
            });
    }

    private function normalizeUsername(mixed $value): ?string
    {
        $username = Str::lower(trim((string) $value));
        $username = preg_replace('/[^a-z0-9._-]+/', '-', $username) ?? '';
        $username = trim($username, '-');
        if ($username !== '' && ! preg_match('/^[a-z]/', $username)) {
            $username = 'user-'.$username;
        }

        return $username === '' ? null : $username;
    }

    private function normalizePhone(mixed $value): ?string
    {
        $phone = preg_replace('/\D+/', '', (string) $value) ?? '';
        if (strlen($phone) < 8) {
            return null;
        }
        if (str_starts_with($phone, '0')) {
            $phone = '62'.substr($phone, 1);
        }

        return $phone;
    }
};

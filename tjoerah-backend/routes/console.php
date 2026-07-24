<?php

use App\Domains\Employee\Models\AttendanceLog;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Storage;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('attendance:purge-photos', function () {
    $purged = 0;
    AttendanceLog::with('outlet.attendancePolicy')
        ->whereNotNull('check_in_at')
        ->orderBy('id')
        ->chunkById(100, function ($records) use (&$purged): void {
            foreach ($records as $record) {
                $retentionDays = $record->outlet?->attendancePolicy?->photo_retention_days ?? 180;
                if ($record->check_in_at->isAfter(now()->subDays($retentionDays))) {
                    continue;
                }

                foreach (['check_in_photo_path', 'check_out_photo_path'] as $column) {
                    $path = $record->getRawOriginal($column);
                    if ($path && Storage::disk('local')->delete($path)) {
                        $record->forceFill([
                            $column => null,
                            str_replace('_path', '_hash', $column) => null,
                        ]);
                        $purged++;
                    }
                }
                if ($record->isDirty()) {
                    $record->save();
                }
            }
        });

    $this->info("Purged {$purged} attendance photos.");
})->purpose('Delete private attendance photos past each outlet retention period');

Schedule::command('attendance:purge-photos')->dailyAt('02:30');

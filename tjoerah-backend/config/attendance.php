<?php

return [
    'photo_disk' => env('ATTENDANCE_FILESYSTEM_DISK', 'local'),
    'photo_max_kilobytes' => (int) env('ATTENDANCE_PHOTO_MAX_KILOBYTES', 1024),
];

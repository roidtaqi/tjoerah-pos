<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendanceLog;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\Employee;
use App\Domains\Employee\Models\EmployeeSchedule;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class AttendanceManagementTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    public function test_employee_can_check_in_and_out_with_photo_location_and_server_time(): void
    {
        Storage::fake('local');
        [$cashier, $employee, $outlet] = $this->attendanceFixture();
        CarbonImmutable::setTestNow('2026-07-24 00:20:00 UTC');
        $this->actingAs($cashier, 'api');

        $context = $this->getJson('/api/attendance/context')
            ->assertOk()
            ->assertJsonPath('employee.id', $employee->id)
            ->assertJsonPath('outlet.id', $outlet->id)
            ->assertJsonPath('policy.late_tolerance_minutes', 10)
            ->json();
        $this->assertNull($context['active_attendance']);

        $requestId = (string) Str::uuid();
        $checkIn = $this->post('/api/attendance/check-in', [
            ...$this->capturePayload($outlet, $requestId),
            'photo' => UploadedFile::fake()->image('check-in.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('attendance.punctuality_status', 'late')
            ->assertJsonPath('attendance.late_minutes', 10)
            ->assertJsonPath('attendance.review_status', 'approved')
            ->assertJsonPath('attendance.has_check_in_photo', true)
            ->json('attendance');

        $attendance = AttendanceLog::findOrFail($checkIn['id']);
        Storage::disk('local')->assertExists($attendance->getRawOriginal('check_in_photo_path'));

        $this->post('/api/attendance/check-in', [
            ...$this->capturePayload($outlet, $requestId),
            'photo' => UploadedFile::fake()->image('retry.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('attendance.id', $attendance->id);
        $this->assertDatabaseCount('attendance_logs', 1);

        CarbonImmutable::setTestNow('2026-07-24 08:30:00 UTC');
        $this->post('/api/attendance/check-out', [
            ...$this->capturePayload($outlet, (string) Str::uuid()),
            'attendance_log_id' => $attendance->id,
            'photo' => UploadedFile::fake()->image('check-out.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('attendance.early_leave_minutes', 30)
            ->assertJsonPath('attendance.has_check_out_photo', true);

        $this->get("/api/attendance/{$attendance->id}/photo/check-in")
            ->assertOk();
    }

    public function test_outside_geofence_requires_reason_and_marks_attendance_for_review(): void
    {
        Storage::fake('local');
        [$cashier, , $outlet] = $this->attendanceFixture();
        CarbonImmutable::setTestNow('2026-07-24 00:00:00 UTC');
        $this->actingAs($cashier, 'api');
        $outside = [
            ...$this->capturePayload($outlet, (string) Str::uuid()),
            'latitude' => -8.7000000,
            'longitude' => 115.2500000,
            'is_mock' => 1,
            'photo' => UploadedFile::fake()->image('outside.jpg', 480, 640),
        ];

        $this->post('/api/attendance/check-in', $outside, ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('outside_reason');

        $this->post('/api/attendance/check-in', [
            ...$outside,
            'request_id' => (string) Str::uuid(),
            'outside_reason' => 'Sedang bertugas membuka booth acara.',
            'photo' => UploadedFile::fake()->image('outside-retry.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('attendance.review_status', 'pending')
            ->assertJsonPath('attendance.check_in_outside_geofence', true)
            ->assertJsonPath('attendance.check_in_is_mock', true);
    }

    public function test_attendance_photo_is_rejected_when_it_exceeds_the_upload_limit(): void
    {
        Storage::fake('local');
        [$cashier, , $outlet] = $this->attendanceFixture();
        $this->actingAs($cashier, 'api');

        $this->post('/api/attendance/check-in', [
            ...$this->capturePayload($outlet, (string) Str::uuid()),
            'photo' => UploadedFile::fake()
                ->image('too-large.jpg', 960, 960)
                ->size(1025),
        ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('photo');

        $this->assertDatabaseCount('attendance_logs', 0);
    }

    public function test_attendance_photo_uses_the_configured_private_disk(): void
    {
        Storage::fake('attendance-photos');
        config(['attendance.photo_disk' => 'attendance-photos']);
        [$cashier, , $outlet] = $this->attendanceFixture();
        $this->actingAs($cashier, 'api');

        $attendanceId = $this->post('/api/attendance/check-in', [
            ...$this->capturePayload($outlet, (string) Str::uuid()),
            'photo' => UploadedFile::fake()->image('check-in.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->json('attendance.id');

        $attendance = AttendanceLog::findOrFail($attendanceId);
        Storage::disk('attendance-photos')->assertExists(
            $attendance->getRawOriginal('check_in_photo_path'),
        );
        $this->get("/api/attendance/{$attendance->id}/photo/check-in")
            ->assertOk();
    }

    public function test_owner_can_manage_policy_schedule_report_and_review(): void
    {
        Storage::fake('local');
        [$cashier, $employee, $outlet, $company] = $this->attendanceFixture();
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $owner->outlets()->attach($outlet);
        CarbonImmutable::setTestNow('2026-07-24 00:00:00 UTC');

        $this->actingAs($owner, 'api')
            ->putJson('/api/attendance/policy', [
                'outlet_id' => $outlet->id,
                'timezone' => 'Asia/Makassar',
                'work_start_time' => '09:00',
                'work_end_time' => '18:00',
                'late_tolerance_minutes' => 15,
                'check_in_open_minutes' => 90,
                'latitude' => -8.6500000,
                'longitude' => 115.2167000,
                'geofence_radius_meters' => 150,
                'maximum_accuracy_meters' => 80,
                'require_check_in_photo' => true,
                'require_check_out_photo' => true,
                'allow_outside_with_reason' => true,
                'photo_retention_days' => 120,
                'is_active' => true,
            ])
            ->assertOk()
            ->assertJsonPath('late_tolerance_minutes', 15);

        $schedule = $this->postJson('/api/attendance/schedules', [
            'employee_id' => $employee->id,
            'outlet_id' => $outlet->id,
            'work_date' => '2026-07-24',
            'start_at' => '2026-07-24T01:00:00Z',
            'end_at' => '2026-07-24T10:00:00Z',
            'shift_name' => 'Shift Pagi',
            'status' => 'scheduled',
        ])->assertCreated()
            ->assertJsonPath('employee.name', $employee->name)
            ->json();

        $attendance = AttendanceLog::create([
            'employee_id' => $employee->id,
            'outlet_id' => $outlet->id,
            'work_date' => '2026-07-24',
            'employee_schedule_id' => $schedule['id'],
            'scheduled_start_at' => '2026-07-24 01:00:00',
            'scheduled_end_at' => '2026-07-24 10:00:00',
            'check_in_at' => '2026-07-24 01:30:00',
            'punctuality_status' => 'late',
            'late_minutes' => 15,
            'review_status' => 'pending',
        ]);

        $this->getJson('/api/attendance/report?date_from=2026-07-24&date_to=2026-07-24')
            ->assertOk()
            ->assertJsonPath('summary.total', 1)
            ->assertJsonPath('summary.late', 1)
            ->assertJsonPath('summary.pending_review', 1)
            ->assertJsonPath('records.data.0.employee.id', $employee->id);

        $this->getJson(
            "/api/attendance/admin-context?outlet_id={$outlet->id}"
            .'&date_from=2026-07-24&date_to=2026-07-24',
        )
            ->assertOk()
            ->assertJsonPath('outlets.0.id', $outlet->id)
            ->assertJsonPath('selected_outlet.id', $outlet->id)
            ->assertJsonPath('policy.outlet_id', $outlet->id)
            ->assertJsonPath('employees.0.id', $employee->id)
            ->assertJsonPath('summary.total', 1)
            ->assertJsonPath('summary.late', 1)
            ->assertJsonPath('records.data.0.id', $attendance->id)
            ->assertJsonPath('schedules.0.id', $schedule['id'])
            ->assertJsonCount(0, 'shifts');

        $this->patchJson("/api/attendance/records/{$attendance->id}/review", [
            'review_status' => 'approved',
            'review_notes' => 'Terlambat karena penugasan pembukaan booth.',
        ])->assertOk()
            ->assertJsonPath('review_status', 'approved')
            ->assertJsonCount(1, 'audits');
        $this->assertDatabaseHas('attendance_audits', [
            'attendance_log_id' => $attendance->id,
            'actor_id' => $owner->id,
        ]);

        $this->get('/api/attendance/export?date_from=2026-07-24&date_to=2026-07-24')
            ->assertOk()
            ->assertHeader('content-type', 'text/csv; charset=UTF-8');

        $this->actingAs($cashier, 'api')
            ->getJson('/api/attendance/report')
            ->assertForbidden();
        $this->getJson('/api/attendance/admin-context')
            ->assertForbidden();
    }

    public function test_owner_can_manage_two_shifts_and_exact_late_boundary_is_applied(): void
    {
        Storage::fake('local');
        [$cashier, $employee, $outlet, $company] = $this->attendanceFixture();
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $owner->outlets()->attach($outlet);

        $morningShift = $this->actingAs($owner, 'api')
            ->postJson('/api/attendance/shifts', [
                'outlet_id' => $outlet->id,
                'name' => 'Shift Pagi',
                'start_time' => '07:30',
                'late_after_time' => '07:45',
                'end_time' => '15:30',
                'check_in_open_minutes' => 60,
                'is_active' => true,
                'sort_order' => 1,
            ])
            ->assertCreated()
            ->assertJsonPath('late_after_time', '07:45')
            ->json();

        $this->postJson('/api/attendance/shifts', [
            'outlet_id' => $outlet->id,
            'name' => 'Shift Kedua',
            'start_time' => '15:30',
            'late_after_time' => '15:45',
            'end_time' => '23:30',
            'check_in_open_minutes' => 60,
            'is_active' => true,
            'sort_order' => 2,
        ])->assertCreated();

        $this->getJson("/api/attendance/shifts?outlet_id={$outlet->id}")
            ->assertOk()
            ->assertJsonCount(2);

        $this->putJson('/api/attendance/shift-assignments', [
            'outlet_id' => $outlet->id,
            'assignments' => [[
                'employee_id' => $employee->id,
                'attendance_shift_id' => $morningShift['id'],
            ]],
        ])->assertOk()
            ->assertJsonPath('0.attendance_shift.name', 'Shift Pagi');

        CarbonImmutable::setTestNow('2026-07-23 23:45:00 UTC');
        $this->actingAs($cashier, 'api')
            ->getJson('/api/attendance/context')
            ->assertOk()
            ->assertJsonCount(2, 'available_shifts')
            ->assertJsonPath('attendance_shift.name', 'Shift Pagi')
            ->assertJsonPath('scheduled_start_at', '2026-07-23T23:30:00.000000Z')
            ->assertJsonPath('scheduled_late_after_at', '2026-07-23T23:45:00.000000Z');

        $attendance = $this->post('/api/attendance/check-in', [
            ...$this->capturePayload($outlet, (string) Str::uuid()),
            'photo' => UploadedFile::fake()->image('shift-check-in.jpg', 480, 640),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('attendance.punctuality_status', 'late')
            ->assertJsonPath('attendance.late_minutes', 1)
            ->assertJsonPath('attendance.attendance_shift.name', 'Shift Pagi')
            ->json('attendance');

        $this->assertDatabaseHas('attendance_logs', [
            'id' => $attendance['id'],
            'attendance_shift_id' => $morningShift['id'],
            'late_minutes' => 1,
        ]);

        $this->actingAs($owner, 'api')
            ->deleteJson("/api/attendance/shifts/{$morningShift['id']}")
            ->assertUnprocessable();
        $this->patchJson("/api/attendance/shifts/{$morningShift['id']}", [
            'is_active' => false,
        ])->assertOk()
            ->assertJsonPath('is_active', false);
    }

    public function test_owner_can_download_prefilled_schedule_template_and_import_it(): void
    {
        [, $employee, $outlet, $company] = $this->attendanceFixture();
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $owner->outlets()->attach($outlet);
        $shift = $this->actingAs($owner, 'api')
            ->postJson('/api/attendance/shifts', [
                'outlet_id' => $outlet->id,
                'name' => 'Shift Pagi',
                'start_time' => '07:30',
                'late_after_time' => '07:45',
                'end_time' => '15:30',
                'check_in_open_minutes' => 60,
                'is_active' => true,
                'sort_order' => 1,
            ])
            ->assertCreated()
            ->json();
        $employee->update(['attendance_shift_id' => $shift['id']]);

        $template = $this->get(
            "/api/attendance/schedules/template?outlet_id={$outlet->id}"
            .'&start_date=2026-07-30&days=2',
        )
            ->assertOk()
            ->assertHeader('content-type', 'text/csv; charset=UTF-8');
        $contents = $template->streamedContent();
        $this->assertStringContainsString($employee->employee_number, $contents);
        $this->assertStringContainsString('Shift Pagi', $contents);

        $csv = implode("\n", [
            'work_date,employee_number,employee_name,shift_name,status,notes',
            "2026-07-30,{$employee->employee_number},{$employee->name},Shift Pagi,scheduled,Opening",
            "2026-07-31,{$employee->employee_number},{$employee->name},,off,Libur",
        ]);
        $this->post('/api/attendance/schedules/import', [
            'outlet_id' => $outlet->id,
            'file' => UploadedFile::fake()->createWithContent(
                'jadwal.csv',
                $csv,
            ),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('imported_schedules', 2)
            ->assertJsonPath('created', 2);

        $this->assertDatabaseCount('employee_schedules', 2);
        $this->assertDatabaseHas('employee_schedules', [
            'employee_id' => $employee->id,
            'attendance_shift_id' => $shift['id'],
            'work_date' => '2026-07-30 00:00:00',
            'shift_name' => 'Shift Pagi',
            'publication_status' => 'draft',
        ]);
        $this->assertDatabaseHas('employee_schedules', [
            'employee_id' => $employee->id,
            'attendance_shift_id' => null,
            'work_date' => '2026-07-31 00:00:00',
            'shift_name' => 'Off',
            'is_custom_time' => false,
        ]);

        $this->postJson('/api/attendance/schedules/publish', [
            'outlet_id' => $outlet->id,
            'date_from' => '2026-07-30',
            'date_to' => '2026-07-31',
        ])->assertOk()->assertJsonPath('published_schedules', 2);
        $this->post('/api/attendance/schedules/import', [
            'outlet_id' => $outlet->id,
            'file' => UploadedFile::fake()->createWithContent(
                'jadwal-update.csv',
                $csv,
            ),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('updated', 2);
        $this->assertDatabaseCount('employee_schedules', 2);
        $this->assertSame(
            2,
            EmployeeSchedule::where('publication_status', 'published')->count(),
        );
    }

    public function test_owner_can_build_publish_and_copy_a_weekly_roster(): void
    {
        [$cashier, $employee, $outlet, $company] = $this->attendanceFixture();
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $owner->outlets()->attach($outlet);
        $this->actingAs($owner, 'api');
        $shiftOne = $this->postJson('/api/attendance/shifts', [
            'outlet_id' => $outlet->id,
            'name' => 'Shift 1',
            'start_time' => '07:30',
            'late_after_time' => '07:45',
            'end_time' => '15:30',
            'check_in_open_minutes' => 60,
            'is_active' => true,
            'sort_order' => 1,
        ])->assertCreated()->json();
        $shiftTwo = $this->postJson('/api/attendance/shifts', [
            'outlet_id' => $outlet->id,
            'name' => 'Shift 2',
            'start_time' => '15:30',
            'late_after_time' => '15:45',
            'end_time' => '23:30',
            'check_in_open_minutes' => 60,
            'is_active' => true,
            'sort_order' => 2,
        ])->assertCreated()->json();
        $pattern = [
            ['attendance_shift_id' => $shiftOne['id'], 'status' => 'scheduled'],
            ['attendance_shift_id' => $shiftTwo['id'], 'status' => 'scheduled'],
            ['attendance_shift_id' => null, 'status' => 'off'],
            ['attendance_shift_id' => $shiftOne['id'], 'status' => 'scheduled'],
            ['attendance_shift_id' => $shiftTwo['id'], 'status' => 'scheduled'],
            ['attendance_shift_id' => $shiftTwo['id'], 'status' => 'scheduled'],
            ['attendance_shift_id' => $shiftTwo['id'], 'status' => 'scheduled'],
        ];
        $assignments = collect($pattern)->map(fn (array $assignment, int $index) => [
            'employee_id' => $employee->id,
            'work_date' => CarbonImmutable::parse('2026-08-03')->addDays($index)->toDateString(),
            ...$assignment,
        ])->all();

        $this->postJson('/api/attendance/schedules/bulk', [
            'outlet_id' => $outlet->id,
            'publication_status' => 'draft',
            'assignments' => $assignments,
        ])->assertOk()
            ->assertJsonPath('updated_schedules', 7);

        $this->actingAs($cashier, 'api')
            ->getJson('/api/attendance/my-schedule?date_from=2026-08-03&date_to=2026-08-09')
            ->assertOk()
            ->assertJsonCount(0);

        $this->actingAs($owner, 'api')
            ->postJson('/api/attendance/schedules/publish', [
                'outlet_id' => $outlet->id,
                'date_from' => '2026-08-03',
                'date_to' => '2026-08-09',
            ])->assertOk()
            ->assertJsonPath('published_schedules', 7);

        $this->actingAs($cashier, 'api')
            ->getJson('/api/attendance/my-schedule?date_from=2026-08-03&date_to=2026-08-09')
            ->assertOk()
            ->assertJsonCount(7)
            ->assertJsonPath('0.attendance_shift.name', 'Shift 1')
            ->assertJsonPath('1.attendance_shift.name', 'Shift 2')
            ->assertJsonPath('2.status', 'off');

        $this->actingAs($owner, 'api')
            ->postJson('/api/attendance/schedules/copy', [
                'outlet_id' => $outlet->id,
                'source_start_date' => '2026-08-03',
                'target_start_date' => '2026-08-10',
                'days' => 7,
            ])->assertOk()
            ->assertJsonPath('copied_schedules', 7);

        $this->assertDatabaseHas('employee_schedules', [
            'employee_id' => $employee->id,
            'work_date' => '2026-08-12 00:00:00',
            'status' => 'off',
            'publication_status' => 'draft',
        ]);
        $this->assertDatabaseCount('employee_schedule_audits', 21);
    }

    public function test_employee_can_request_change_and_admin_can_approve_custom_hours(): void
    {
        [$cashier, $employee, $outlet, $company] = $this->attendanceFixture();
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'admin',
        ]);
        $owner->outlets()->attach($outlet);
        $shift = $this->actingAs($owner, 'api')
            ->postJson('/api/attendance/shifts', [
                'outlet_id' => $outlet->id,
                'name' => 'Shift 1',
                'start_time' => '07:30',
                'late_after_time' => '07:45',
                'end_time' => '15:30',
                'check_in_open_minutes' => 60,
                'is_active' => true,
                'sort_order' => 1,
            ])->assertCreated()->json();
        $schedule = $this->postJson('/api/attendance/schedules/bulk', [
            'outlet_id' => $outlet->id,
            'publication_status' => 'published',
            'assignments' => [[
                'employee_id' => $employee->id,
                'work_date' => '2026-08-05',
                'attendance_shift_id' => $shift['id'],
                'status' => 'scheduled',
            ]],
        ])->assertOk()->json('schedules.0');

        CarbonImmutable::setTestNow('2026-08-01 00:00:00 UTC');
        $changeRequest = $this->actingAs($cashier, 'api')
            ->postJson('/api/attendance/change-requests', [
                'requested_work_date' => '2026-08-05',
                'requested_status' => 'scheduled',
                'requested_attendance_shift_id' => $shift['id'],
                'reason' => 'Perlu mengganti jam kerja pada hari tersebut.',
            ])->assertCreated()
            ->assertJsonPath('request.employee_schedule_id', $schedule['id'])
            ->json('request');

        $this->actingAs($owner, 'api')
            ->getJson("/api/attendance/admin/change-requests?outlet_id={$outlet->id}")
            ->assertOk()
            ->assertJsonPath('0.id', $changeRequest['id']);

        $this->patchJson("/api/attendance/admin/change-requests/{$changeRequest['id']}/review", [
            'decision' => 'approved',
            'status' => 'scheduled',
            'custom_start_time' => '10:00',
            'custom_late_after_time' => '10:15',
            'custom_end_time' => '18:00',
            'response_notes' => 'Disetujui sebagai jam kerja cadangan.',
        ])->assertOk()
            ->assertJsonPath('request.status', 'approved')
            ->assertJsonPath('schedule.shift_name', 'Jam khusus')
            ->assertJsonPath('schedule.is_custom_time', true);

        $this->assertDatabaseHas('employee_schedules', [
            'id' => $schedule['id'],
            'publication_status' => 'published',
            'is_custom_time' => true,
            'change_reason' => 'Disetujui sebagai jam kerja cadangan.',
        ]);
        $this->actingAs($cashier, 'api')
            ->getJson('/api/attendance/change-requests')
            ->assertOk()
            ->assertJsonPath('0.status', 'approved');
    }

    public function test_employee_cannot_view_another_company_attendance_photo(): void
    {
        Storage::fake('local');
        [$cashier] = $this->attendanceFixture();
        [$otherUser, $otherEmployee, $otherOutlet] = $this->attendanceFixture('Other Company');
        $path = UploadedFile::fake()->image('private.jpg')->store('attendance/private', 'local');
        $attendance = AttendanceLog::create([
            'employee_id' => $otherEmployee->id,
            'outlet_id' => $otherOutlet->id,
            'work_date' => '2026-07-24',
            'check_in_at' => now(),
            'check_in_photo_path' => $path,
        ]);

        $this->actingAs($cashier, 'api')
            ->get("/api/attendance/{$attendance->id}/photo/check-in")
            ->assertNotFound();
        $this->actingAs($otherUser, 'api')
            ->get("/api/attendance/{$attendance->id}/photo/check-in")
            ->assertOk();
    }

    public function test_admin_outlet_list_is_limited_to_their_company(): void
    {
        [, , $outlet, $company] = $this->attendanceFixture();
        [, , $foreignOutlet] = $this->attendanceFixture('Foreign Company');
        $admin = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'admin',
        ]);

        $response = $this->actingAs($admin, 'api')
            ->getJson('/api/attendance/outlets')
            ->assertOk()
            ->assertJsonCount(1);

        $this->assertSame($outlet->id, $response->json('0.id'));
        $this->assertNotSame($foreignOutlet->id, $response->json('0.id'));
    }

    public function test_inactive_attendance_policy_blocks_new_check_in(): void
    {
        Storage::fake('local');
        [$cashier, , $outlet] = $this->attendanceFixture();
        $outlet->attendancePolicy()->update(['is_active' => false]);

        $this->actingAs($cashier, 'api')
            ->post('/api/attendance/check-in', [
                ...$this->capturePayload($outlet, (string) Str::uuid()),
                'photo' => UploadedFile::fake()->image('check-in.jpg', 480, 640),
            ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('attendance');
    }

    public function test_non_working_schedule_blocks_check_in(): void
    {
        Storage::fake('local');
        [$cashier, $employee, $outlet] = $this->attendanceFixture();
        CarbonImmutable::setTestNow('2026-07-24 00:00:00 UTC');
        EmployeeSchedule::create([
            'employee_id' => $employee->id,
            'outlet_id' => $outlet->id,
            'work_date' => '2026-07-24',
            'start_at' => '2026-07-24 00:00:00',
            'end_at' => '2026-07-24 09:00:00',
            'shift_name' => 'Cuti tahunan',
            'status' => 'leave',
        ]);

        $this->actingAs($cashier, 'api')
            ->post('/api/attendance/check-in', [
                ...$this->capturePayload($outlet, (string) Str::uuid()),
                'photo' => UploadedFile::fake()->image('check-in.jpg', 480, 640),
            ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('attendance');
    }

    public function test_manager_without_company_id_is_scoped_to_assigned_outlets(): void
    {
        Storage::fake('local');
        [, $employee, $outlet] = $this->attendanceFixture();
        [, $foreignEmployee, $foreignOutlet] = $this->attendanceFixture('Foreign Company');
        $manager = User::factory()->create([
            'company_id' => null,
            'role' => 'owner',
        ]);
        $manager->outlets()->attach($outlet);

        AttendanceLog::create([
            'employee_id' => $employee->id,
            'outlet_id' => $outlet->id,
            'work_date' => '2026-07-24',
            'check_in_at' => now(),
        ]);
        $foreignPhoto = UploadedFile::fake()
            ->image('private.jpg')
            ->store('attendance/private', 'local');
        $foreignAttendance = AttendanceLog::create([
            'employee_id' => $foreignEmployee->id,
            'outlet_id' => $foreignOutlet->id,
            'work_date' => '2026-07-24',
            'check_in_at' => now(),
            'check_in_photo_path' => $foreignPhoto,
        ]);

        $this->actingAs($manager, 'api')
            ->getJson('/api/attendance/report?date_from=2026-07-24&date_to=2026-07-24')
            ->assertOk()
            ->assertJsonPath('summary.total', 1)
            ->assertJsonPath('records.data.0.outlet_id', $outlet->id);

        $this->get("/api/attendance/{$foreignAttendance->id}/photo/check-in")
            ->assertNotFound();
        $this->getJson("/api/attendance/policy?outlet_id={$foreignOutlet->id}")
            ->assertNotFound();
        $this->getJson("/api/employees?outlet_id={$foreignOutlet->id}")
            ->assertOk()
            ->assertJsonPath('total', 0);
    }

    private function attendanceFixture(string $companyName = 'Tjoerah'): array
    {
        $company = Company::create(['name' => $companyName]);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'name' => "{$companyName} Main Outlet",
            'timezone' => 'Asia/Makassar',
            'is_active' => true,
        ]);
        $cashier = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);
        $cashier->outlets()->attach($outlet);
        $employee = Employee::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'user_id' => $cashier->id,
            'employee_number' => 'EMP-'.$cashier->id,
            'name' => $cashier->name,
            'position' => 'Cashier',
            'is_active' => true,
        ]);
        AttendancePolicy::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'timezone' => 'Asia/Makassar',
            'work_start_time' => '08:00',
            'work_end_time' => '17:00',
            'late_tolerance_minutes' => 10,
            'check_in_open_minutes' => 60,
            'latitude' => -8.6500000,
            'longitude' => 115.2167000,
            'geofence_radius_meters' => 100,
            'maximum_accuracy_meters' => 100,
            'require_check_in_photo' => true,
            'require_check_out_photo' => true,
            'allow_outside_with_reason' => true,
            'is_active' => true,
        ]);

        return [$cashier, $employee, $outlet, $company];
    }

    private function capturePayload(Outlet $outlet, string $requestId): array
    {
        return [
            'outlet_id' => $outlet->id,
            'latitude' => -8.6500000,
            'longitude' => 115.2167000,
            'accuracy_meters' => 12,
            'is_mock' => 0,
            'device_captured_at' => CarbonImmutable::now('UTC')->toIso8601String(),
            'device_id' => 'test-device',
            'request_id' => $requestId,
            'source' => 'mobile',
        ];
    }
}

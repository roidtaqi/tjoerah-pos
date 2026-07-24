<?php

use App\Domains\Core\Controllers\AuthController;
use App\Domains\Core\Controllers\OrganizationController;
use App\Domains\Core\Controllers\OutletController;
use App\Domains\Core\Controllers\RbacController;
use App\Domains\CRM\Controllers\CustomerController;
use App\Domains\Employee\Controllers\AttendanceController;
use App\Domains\Employee\Controllers\EmployeeController;
use App\Domains\Inventory\Controllers\InventoryController;
use App\Domains\Inventory\Controllers\PurchaseController;
use App\Domains\Inventory\Controllers\WastageController;
use App\Domains\KDS\Controllers\KdsController;
use App\Domains\POS\Controllers\PaymentController;
use App\Domains\POS\Controllers\ProductCatalogController;
use App\Domains\POS\Controllers\ReceiptController;
use App\Domains\POS\Controllers\SyncController;
use App\Domains\POS\Controllers\TableManagementController;
use App\Domains\Recipe\Controllers\RecipeController;
use App\Domains\Reporting\Controllers\ReportingController;
use App\Domains\Sales\Controllers\OrderController;
use Illuminate\Support\Facades\Route;

Route::post('/login', [AuthController::class, 'login']);
Route::post('/auth/login', [AuthController::class, 'login']);
Route::post('/auth/pin/login', [AuthController::class, 'pinLogin']);

Route::middleware('auth:api')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::post('/auth/refresh', [AuthController::class, 'refresh']);
    Route::post('/auth/device/register', [AuthController::class, 'registerDevice']);

    Route::get('/companies', [OrganizationController::class, 'companies']);
    Route::post('/companies', [OrganizationController::class, 'storeCompany']);
    Route::get('/brands', [OrganizationController::class, 'brands']);
    Route::post('/brands', [OrganizationController::class, 'storeBrand']);
    Route::apiResource('outlets', OutletController::class);

    Route::get('/roles', [RbacController::class, 'roles']);
    Route::post('/roles', [RbacController::class, 'storeRole']);
    Route::get('/permissions', [RbacController::class, 'permissions']);
    Route::post('/roles/{role}/permissions', [RbacController::class, 'attachPermissions']);
    Route::post('/users/{user}/roles', [RbacController::class, 'assignRole']);

    // Catalog API
    Route::get('/catalog/sync', [ProductCatalogController::class, 'sync']);
    Route::get('/categories', [ProductCatalogController::class, 'categories']);
    Route::get('/categories/{category}', [ProductCatalogController::class, 'showCategory']);
    Route::get('/products', [ProductCatalogController::class, 'getProducts']);
    Route::get('/products/search', [ProductCatalogController::class, 'search']);
    Route::get('/products/{product}', [ProductCatalogController::class, 'showProduct']);
    Route::get('/modifier-groups', [ProductCatalogController::class, 'modifierGroups']);

    Route::middleware('role:owner,admin')->group(function () {
        Route::post('/categories', [ProductCatalogController::class, 'storeCategory']);
        Route::match(['put', 'patch'], '/categories/{category}', [ProductCatalogController::class, 'updateCategory']);
        Route::delete('/categories/{category}', [ProductCatalogController::class, 'destroyCategory']);
        Route::post('/products', [ProductCatalogController::class, 'storeProduct']);
        Route::match(['put', 'patch'], '/products/{product}', [ProductCatalogController::class, 'updateProduct']);
        Route::delete('/products/{product}', [ProductCatalogController::class, 'destroyProduct']);
    });

    Route::post('/orders', [OrderController::class, 'store']);
    Route::get('/orders/{order}', [OrderController::class, 'show']);
    Route::post('/orders/{order}/hold', [OrderController::class, 'hold']);
    Route::post('/orders/{order}/resume', [OrderController::class, 'resume']);
    Route::post('/orders/{order}/void', [OrderController::class, 'void']);
    Route::post('/orders/{order}/refund', [OrderController::class, 'refund']);
    Route::post('/orders/{order}/complete', [OrderController::class, 'complete']);
    Route::post('/payments', [PaymentController::class, 'store']);
    Route::get('/receipts/{order}', [ReceiptController::class, 'show']);

    Route::get('/floors', [TableManagementController::class, 'floors']);
    Route::post('/floors', [TableManagementController::class, 'storeFloor']);
    Route::patch('/floors/{floor}', [TableManagementController::class, 'updateFloor']);
    Route::delete('/floors/{floor}', [TableManagementController::class, 'destroyFloor']);
    Route::get('/tables', [TableManagementController::class, 'tables']);
    Route::post('/tables', [TableManagementController::class, 'storeTable']);
    Route::patch('/tables/{table}', [TableManagementController::class, 'updateTable']);
    Route::delete('/tables/{table}', [TableManagementController::class, 'destroyTable']);
    Route::post('/table-sessions', [TableManagementController::class, 'openSession']);
    Route::post('/table-sessions/{session}/close', [TableManagementController::class, 'closeSession']);

    Route::get('/kds/tickets', [KdsController::class, 'tickets']);
    Route::post('/kds/tickets/{ticket}/status', [KdsController::class, 'updateStatus']);

    Route::get('/inventory', [InventoryController::class, 'index']);
    Route::post('/inventory/items', [InventoryController::class, 'storeItem']);
    Route::get('/inventory/warehouses', [InventoryController::class, 'warehouses']);
    Route::post('/inventory/warehouses', [InventoryController::class, 'storeWarehouse']);
    Route::get('/inventory/movements', [InventoryController::class, 'movements']);
    Route::post('/inventory/adjustments', [InventoryController::class, 'adjustment']);
    Route::post('/inventory/opname', [InventoryController::class, 'opname']);
    Route::post('/inventory/transfers', [InventoryController::class, 'transfer']);
    Route::post('/inventory/wastage', [WastageController::class, 'store']);

    Route::get('/recipes', [RecipeController::class, 'index']);
    Route::post('/recipes', [RecipeController::class, 'store']);
    Route::put('/recipes/{recipe}', [RecipeController::class, 'update']);
    Route::post('/recipes/version', [RecipeController::class, 'version']);
    Route::get('/recipes/costing', [RecipeController::class, 'costing']);

    Route::get('/suppliers', [PurchaseController::class, 'suppliers']);
    Route::post('/suppliers', [PurchaseController::class, 'storeSupplier']);
    Route::get('/purchase-orders', [PurchaseController::class, 'purchaseOrders']);
    Route::post('/purchase-orders', [PurchaseController::class, 'storePurchaseOrder']);
    Route::post('/goods-receipts', [PurchaseController::class, 'storeGoodsReceipt']);

    Route::get('/customers', [CustomerController::class, 'index']);
    Route::post('/customers', [CustomerController::class, 'store']);
    Route::post('/loyalty/earn', [CustomerController::class, 'earn']);
    Route::post('/loyalty/redeem', [CustomerController::class, 'redeem']);
    Route::post('/vouchers/validate', [CustomerController::class, 'validateVoucher']);

    Route::get('/attendance/context', [AttendanceController::class, 'context']);
    Route::get('/attendance/my-history', [AttendanceController::class, 'myHistory']);
    Route::post('/attendance/check-in', [AttendanceController::class, 'checkIn']);
    Route::post('/attendance/check-out', [AttendanceController::class, 'checkOut']);
    Route::post('/attendance/checkin', [AttendanceController::class, 'checkIn']);
    Route::post('/attendance/checkout', [AttendanceController::class, 'checkOut']);
    Route::get('/attendance/{attendance}/photo/{type}', [AttendanceController::class, 'photo']);

    Route::middleware('role:owner,admin')->group(function () {
        Route::get('/employees', [EmployeeController::class, 'index']);
        Route::post('/employees', [EmployeeController::class, 'store']);
        Route::match(['put', 'patch'], '/employees/{employee}', [EmployeeController::class, 'update']);
        Route::delete('/employees/{employee}', [EmployeeController::class, 'destroy']);
        Route::get('/attendance/outlets', [AttendanceController::class, 'outlets']);
        Route::get('/attendance/report', [AttendanceController::class, 'report']);
        Route::get('/attendance/export', [AttendanceController::class, 'export']);
        Route::get('/attendance/policy', [AttendanceController::class, 'policy']);
        Route::put('/attendance/policy', [AttendanceController::class, 'updatePolicy']);
        Route::get('/attendance/shifts', [AttendanceController::class, 'attendanceShifts']);
        Route::post('/attendance/shifts', [AttendanceController::class, 'storeAttendanceShift']);
        Route::match(['put', 'patch'], '/attendance/shifts/{attendanceShift}', [AttendanceController::class, 'updateAttendanceShift']);
        Route::delete('/attendance/shifts/{attendanceShift}', [AttendanceController::class, 'destroyAttendanceShift']);
        Route::put('/attendance/shift-assignments', [AttendanceController::class, 'assignAttendanceShifts']);
        Route::get('/attendance/schedules', [AttendanceController::class, 'schedules']);
        Route::post('/attendance/schedules', [AttendanceController::class, 'storeSchedule']);
        Route::match(['put', 'patch'], '/attendance/schedules/{schedule}', [AttendanceController::class, 'updateSchedule']);
        Route::delete('/attendance/schedules/{schedule}', [AttendanceController::class, 'destroySchedule']);
        Route::patch('/attendance/records/{attendance}/review', [AttendanceController::class, 'review']);
    });

    Route::post('/shifts/start', [EmployeeController::class, 'startShift']);
    Route::post('/shifts/end', [EmployeeController::class, 'endShift']);

    Route::get('/reports/sales', [ReportingController::class, 'sales']);
    Route::get('/reports/products', [ReportingController::class, 'products']);
    Route::get('/reports/inventory', [ReportingController::class, 'inventory']);
    Route::get('/reports/profitability', [ReportingController::class, 'profitability']);
    Route::get('/reports/outlets', [ReportingController::class, 'outlets']);
    Route::get('/reports/alerts', [ReportingController::class, 'alerts']);

    Route::get('/sync/pull', [SyncController::class, 'pull']);
    Route::post('/sync/push', [SyncController::class, 'push']);
    Route::get('/sync/conflicts', [SyncController::class, 'conflicts']);
});

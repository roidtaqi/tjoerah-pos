<?php
$domainMapping = [
    'Customer' => 'CRM', 'CustomerReward' => 'CRM', 'LoyaltyPoint' => 'CRM', 'Membership' => 'CRM', 'Promotion' => 'CRM', 'Voucher' => 'CRM',
    'Employee' => 'Employee', 'Shift' => 'Employee', 'AttendanceLog' => 'Employee',
    'InventoryItem' => 'Inventory', 'StockMovement' => 'Inventory', 'StockAdjustment' => 'Inventory', 'StockOpname' => 'Inventory', 'Warehouse' => 'Inventory', 'GoodsReceipt' => 'Inventory', 'PurchaseOrder' => 'Inventory', 'PurchaseOrderItem' => 'Inventory', 'Supplier' => 'Inventory', 'Wastage' => 'Inventory',
    'KitchenTicket' => 'KDS', 'KitchenTicketItem' => 'KDS',
    'Order' => 'POS', 'OrderItem' => 'POS', 'Payment' => 'POS', 'VoidTransaction' => 'POS', 'Refund' => 'POS', 'Category' => 'POS', 'Product' => 'POS', 'ProductVariant' => 'POS', 'ModifierGroup' => 'POS', 'ModifierOption' => 'POS', 'Floor' => 'POS', 'DiningTable' => 'POS', 'TableSession' => 'POS', 'SyncBatch' => 'POS', 'SyncConflict' => 'POS',
    'Recipe' => 'Recipe', 'RecipeItem' => 'Recipe', 'RecipeVersion' => 'Recipe', 'RecipeYield' => 'Recipe',
    'ActivityLog' => 'Reporting', 'AuditLog' => 'Reporting', 'PriceHistory' => 'Reporting', 'ProfitabilitySnapshot' => 'Reporting', 'SystemAlert' => 'Reporting',
    'Brand' => 'Core', 'Company' => 'Core', 'Outlet' => 'Core', 'User' => 'Core', 'Role' => 'Core', 'Permission' => 'Core'
];

$basePath = __DIR__ . '/tjoerah-backend';
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($basePath . '/app/Domains'));

foreach ($iterator as $file) {
    if ($file->isFile() && $file->getExtension() === 'php' && strpos($file->getPathname(), '/Models/') !== false) {
        $content = file_get_contents($file->getPathname());
        $changed = false;
        
        foreach ($domainMapping as $model => $domain) {
            // Replace short class references with Fully Qualified Class Names inside relationships
            // Matches: hasMany(Model::class
            $pattern = "/(hasMany|belongsTo|hasOne|belongsToMany|morphTo|morphMany|morphToMany)\(\s*{$model}::class/";
            $fqcn = "\\App\\Domains\\{$domain}\\Models\\{$model}::class";
            if (preg_match($pattern, $content)) {
                $content = preg_replace($pattern, "$1($fqcn", $content);
                $changed = true;
            }
        }
        
        if ($changed) {
            file_put_contents($file->getPathname(), $content);
            echo "Updated relationships in " . $file->getBasename() . "\n";
        }
    }
}

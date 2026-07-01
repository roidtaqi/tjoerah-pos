<?php
$file = "tjoerah-backend/database/migrations/2026_07_01_100000_create_enterprise_foundation_tables.php";
$content = file_get_contents($file);

$tablesToUpdate = [
    'orders', 'order_items', 'payments', 'void_transactions', 'refunds', 
    'kitchen_tickets', 'kitchen_ticket_items'
];

foreach ($tablesToUpdate as $table) {
    // Replace $table->id(); with $table->uuid('id')->primary();
    $pattern = "/Schema::create\(\x27{$table}\x27,\s*function\s*\(Blueprint\s*\\\$table\)\s*\{\s*\\\$table->id\(\);/s";
    $replacement = "Schema::create('{$table}', function (Blueprint \$table) {\n            \$table->uuid('id')->primary();";
    $content = preg_replace($pattern, $replacement, $content);
    
    // Also, if any of these tables have foreign keys pointing to other UUID tables, we must change them from foreignId to foreignUuid
    if ($table === 'order_items' || $table === 'payments' || $table === 'void_transactions' || $table === 'refunds' || $table === 'kitchen_tickets' || $table === 'kitchen_ticket_items') {
        $content = preg_replace("/\\\$table->foreignId\(\x27order_id\x27\)/", "\$table->foreignUuid('order_id')", $content);
        $content = preg_replace("/\\\$table->foreignId\(\x27kitchen_ticket_id\x27\)/", "\$table->foreignUuid('kitchen_ticket_id')", $content);
    }
}

file_put_contents($file, $content);
echo "Migrations updated to use UUID.\n";

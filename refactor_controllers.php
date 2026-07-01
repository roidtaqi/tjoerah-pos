<?php

$controllerMapping = [
    'CRM' => ['CustomerController'],
    'Employee' => ['EmployeeController'],
    'Inventory' => ['InventoryController', 'PurchaseController'],
    'KDS' => ['KdsController'],
    'POS' => ['ProductCatalogController', 'PaymentController', 'ReceiptController', 'SyncController', 'TableManagementController'],
    'Recipe' => ['RecipeController'],
    'Reporting' => ['ReportingController'],
    'Core' => ['AuthController', 'OutletController', 'OrganizationController', 'RbacController']
];

$basePath = __DIR__ . '/tjoerah-backend';
mkdir($basePath . '/app/Domains/Core/Controllers', 0777, true);
mkdir($basePath . '/app/Domains/Core/Models', 0777, true);

// 1. Move controllers
foreach ($controllerMapping as $domain => $controllers) {
    foreach ($controllers as $controller) {
        $pathsToTry = [
            $basePath . "/app/Http/Controllers/{$controller}.php",
            $basePath . "/app/Http/Controllers/Api/{$controller}.php",
        ];
        
        foreach ($pathsToTry as $oldPath) {
            if (file_exists($oldPath)) {
                $newPath = $basePath . "/app/Domains/{$domain}/Controllers/{$controller}.php";
                
                $content = file_get_contents($oldPath);
                // Update namespace
                $content = preg_replace('/namespace App\\\\Http\\\\Controllers(?:\\\\Api)?;/', "namespace App\Domains\\{$domain}\Controllers;", $content);
                // Make sure they use the base controller if needed
                if (!strpos($content, 'use App\Http\Controllers\Controller;')) {
                    $content = str_replace("class {$controller}", "use App\Http\Controllers\Controller;\n\nclass {$controller}", $content);
                }
                
                file_put_contents($newPath, $content);
                unlink($oldPath);
                echo "Moved $controller to $domain\n";
                break;
            }
        }
    }
}

// 2. Global search and replace for Controller references in routes
$allControllers = [];
foreach ($controllerMapping as $domain => $controllers) {
    foreach ($controllers as $controller) {
        $allControllers[$controller] = $domain;
    }
}

$routeFiles = [
    $basePath . '/routes/api.php',
    $basePath . '/routes/web.php',
];

foreach ($routeFiles as $routeFile) {
    if (file_exists($routeFile)) {
        $content = file_get_contents($routeFile);
        $changed = false;
        
        foreach ($allControllers as $controller => $domain) {
            // Replace use App\Http\Controllers\ControllerName;
            $oldUse1 = "use App\Http\Controllers\\$controller;";
            $oldUse2 = "use App\Http\Controllers\Api\\$controller;";
            $newUse = "use App\Domains\\$domain\Controllers\\$controller;";
            
            if (strpos($content, $oldUse1) !== false) {
                $content = str_replace($oldUse1, $newUse, $content);
                $changed = true;
            }
            if (strpos($content, $oldUse2) !== false) {
                $content = str_replace($oldUse2, $newUse, $content);
                $changed = true;
            }
            
            // Handle inline array syntax `[\App\Http\Controllers\Api\Controller::class, ...]`
            $oldInline1 = "\App\Http\Controllers\\$controller";
            $oldInline2 = "\App\Http\Controllers\Api\\$controller";
            $newInline = "\App\Domains\\$domain\Controllers\\$controller";
            
            if (strpos($content, $oldInline1) !== false) {
                $content = str_replace($oldInline1, $newInline, $content);
                $changed = true;
            }
            if (strpos($content, $oldInline2) !== false) {
                $content = str_replace($oldInline2, $newInline, $content);
                $changed = true;
            }
        }
        
        if ($changed) {
            file_put_contents($routeFile, $content);
        }
    }
}

echo "Controllers Refactored.\n";

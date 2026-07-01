<?php

$domainMapping = [
    'Core' => ['Brand', 'Company', 'Outlet', 'User', 'Role', 'Permission']
];

$basePath = __DIR__ . '/tjoerah-backend';

// Move Models
foreach ($domainMapping as $domain => $models) {
    foreach ($models as $model) {
        $oldPath = $basePath . "/app/Models/{$model}.php";
        $newPath = $basePath . "/app/Domains/{$domain}/Models/{$model}.php";
        
        if (file_exists($oldPath)) {
            $content = file_get_contents($oldPath);
            $content = str_replace('namespace App\Models;', "namespace App\Domains\\{$domain}\Models;", $content);
            file_put_contents($newPath, $content);
            unlink($oldPath);
            echo "Moved $model to $domain\n";
        }
    }
}

// Move Concerns directory
$oldConcerns = $basePath . '/app/Models/Concerns';
$newConcerns = $basePath . '/app/Domains/Core/Models/Concerns';
if (is_dir($oldConcerns)) {
    rename($oldConcerns, $newConcerns);
    // update namespace in concerns
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($newConcerns));
    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $content = file_get_contents($file->getPathname());
            $content = str_replace('namespace App\Models\Concerns;', 'namespace App\Domains\Core\Models\Concerns;', $content);
            file_put_contents($file->getPathname(), $content);
        }
    }
}

// Global search and replace
$allModels = [];
foreach ($domainMapping as $domain => $models) {
    foreach ($models as $model) {
        $allModels[$model] = $domain;
    }
}

$directories = ['/app', '/database', '/routes', '/tests', '/bootstrap', '/config'];

function replaceInDir($dir, $allModels, $basePath) {
    if (!is_dir($basePath . $dir)) return;
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($basePath . $dir));
    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $content = file_get_contents($file->getPathname());
            $changed = false;
            
            foreach ($allModels as $model => $domain) {
                // Replace `use App\Models\Model;` -> `use App\Domains\Domain\Models\Model;`
                $oldUse = "use App\Models\\$model;";
                $newUse = "use App\Domains\\$domain\Models\\$model;";
                if (strpos($content, $oldUse) !== false) {
                    $content = str_replace($oldUse, $newUse, $content);
                    $changed = true;
                }
                
                // Also handle inline instantiations like `\App\Models\Model::class`
                $oldInline = "\App\Models\\$model";
                $newInline = "\App\Domains\\$domain\Models\\$model";
                if (strpos($content, $oldInline) !== false) {
                    $content = str_replace($oldInline, $newInline, $content);
                    $changed = true;
                }
            }
            
            // Fix Concerns traits usage
            $oldConcernUse = 'use App\Models\Concerns';
            $newConcernUse = 'use App\Domains\Core\Models\Concerns';
            if (strpos($content, $oldConcernUse) !== false) {
                $content = str_replace($oldConcernUse, $newConcernUse, $content);
                $changed = true;
            }
            
            if ($changed) {
                file_put_contents($file->getPathname(), $content);
            }
        }
    }
}

foreach ($directories as $dir) {
    replaceInDir($dir, $allModels, $basePath);
}

// Clean up old Models directory if empty
@rmdir($basePath . '/app/Models');

echo "Core Models Refactored.\n";

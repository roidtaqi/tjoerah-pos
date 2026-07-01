<?php
$basePath = __DIR__ . '/tjoerah-backend';
$directories = ['/tests', '/config', '/app', '/database'];

foreach ($directories as $dir) {
    if (!is_dir($basePath . $dir)) continue;
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($basePath . $dir));
    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $content = file_get_contents($file->getPathname());
            $changed = false;
            
            if (strpos($content, 'App\User') !== false) {
                $content = str_replace('App\User', 'App\Domains\Core\Models\User', $content);
                $changed = true;
            }
            if (strpos($content, 'use App\Domains\Core\Models\UserFactory;') !== false) {
                $content = str_replace('use App\Domains\Core\Models\UserFactory;', 'use Database\Factories\UserFactory;', $content);
                $changed = true;
            }
            
            if ($changed) {
                file_put_contents($file->getPathname(), $content);
            }
        }
    }
}
echo "Fixed App\\User references.\n";

<?php
$file = __DIR__ . '/tjoerah-backend/app/Providers/AppServiceProvider.php';
$content = file_get_contents($file);

if (strpos($content, 'use Illuminate\Database\Eloquent\Factories\Factory;') === false) {
    $content = str_replace('use Illuminate\Support\ServiceProvider;', "use Illuminate\Support\ServiceProvider;\nuse Illuminate\Database\Eloquent\Factories\Factory;\nuse Illuminate\Support\Str;", $content);
}

if (strpos($content, 'Factory::guessFactoryNamesUsing') === false) {
    $resolver = <<<RESOLVER
        Factory::guessFactoryNamesUsing(function (string \$modelName) {
            // Map App\Domains\Core\Models\User to Database\Factories\UserFactory
            if (Str::startsWith(\$modelName, 'App\\\Domains\\\\')) {
                \$className = class_basename(\$modelName);
                return 'Database\\\Factories\\\\' . \$className . 'Factory';
            }
            return 'Database\\\Factories\\\\' . class_basename(\$modelName) . 'Factory';
        });
RESOLVER;

    $content = str_replace('public function boot(): void', "public function boot(): void\n    {\n" . $resolver, $content);
    // Remove the extra { if any
    $content = str_replace("public function boot(): void\n    {\n{$resolver}\n    {", "public function boot(): void\n    {\n{$resolver}", $content);
}
file_put_contents($file, $content);

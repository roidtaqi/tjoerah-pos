<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

use Illuminate\Support\Facades\Event;
use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\Inventory\Listeners\DeductInventoryOnOrderCompletion;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Factory::guessFactoryNamesUsing(function (string $modelName) {
            // Map App\Domains\Core\Models\User to Database\Factories\UserFactory
            if (Str::startsWith($modelName, 'App\\Domains\\')) {
                $className = class_basename($modelName);
                return 'Database\\Factories\\' . $className . 'Factory';
            }
            return 'Database\\Factories\\' . class_basename($modelName) . 'Factory';
        });

        Event::listen(
            OrderCompleted::class,
            DeductInventoryOnOrderCompletion::class
        );

        Event::listen(
            OrderCompleted::class,
            \App\Domains\CRM\Listeners\AwardLoyaltyPointsListener::class
        );
    }
}

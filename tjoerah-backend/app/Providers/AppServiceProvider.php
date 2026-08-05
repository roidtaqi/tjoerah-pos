<?php

namespace App\Providers;

use App\Domains\CRM\Listeners\AwardLoyaltyPointsListener;
use App\Domains\Inventory\Listeners\DeductInventoryOnOrderSubmission;
use App\Domains\POS\Listeners\RecordCashSaleOnOrderCompleted;
use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\Sales\Events\OrderSubmitted;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

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

                return 'Database\\Factories\\'.$className.'Factory';
            }

            return 'Database\\Factories\\'.class_basename($modelName).'Factory';
        });

        Event::listen(
            OrderSubmitted::class,
            DeductInventoryOnOrderSubmission::class
        );

        Event::listen(
            OrderCompleted::class,
            AwardLoyaltyPointsListener::class
        );

        Event::listen(
            OrderCompleted::class,
            RecordCashSaleOnOrderCompleted::class
        );
    }
}

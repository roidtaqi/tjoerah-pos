<?php

namespace App\Domains\Core\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Domains\Core\Models\Concerns\HasUuid;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasUuid, Notifiable, SoftDeletes;

    protected $guarded = [];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function outlets(): BelongsToMany
    {
        return $this->belongsToMany(\App\Domains\Core\Models\Outlet::class);
    }

    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(\App\Domains\Core\Models\Role::class, 'user_roles')
            ->withPivot(['company_id', 'brand_id', 'outlet_id'])
            ->withTimestamps();
    }
}
